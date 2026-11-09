# OUTSIDER: a área Teams do menu (chats e canais do "Conectar meu Teams"). Cada pessoa só enxerga a própria área:
# tudo sai da ligação dela (Outsider::TeamsLink do usuário atual); administradores não leem a área dos outros.
#   index: lista de chats (kind=chat) ou de canais (kind=channel), com as não lidas e as menções.
#   summary: números para o menu (não lidas em chats e canais) e a situação da ligação.
#   messages: últimas mensagens do chat; no canal, últimas publicações com as respostas, ou (mode=flat) tudo em
#     sequência, como no WhatsApp, com a citação da publicação em cada resposta; before = id para trás.
#   send_message: escreve no Teams (citação com quote_id; no canal, resposta com reply_to_graph_id ou publicação nova).
#     Arquivos vão para o OneDrive/SharePoint na hora; imagens pequenas vão dentro da mensagem. Nada fica no Chatwoot.
#   preview: endereço da visualização do arquivo (OneDrive/SharePoint), só para ler, no visualizador do Chatwoot.
#   members: quem dá para @mencionar (participantes do chat; no canal, quem já escreveu nele).
#   read: zera as não lidas e as menções.
#   react: reage a uma mensagem (ou tira a reação) em nome da pessoa, como no Teams.
#   mentions: as mensagens que citaram a pessoa neste chat ou canal (últimos 60 dias), para ir de uma a outra.
class Api::V1::Accounts::Outsider::TeamsThreadsController < Api::V1::Accounts::BaseController
  CHAT_PAGE = 50
  MENTION_DAYS = 60
  MAX_MENTIONS = 50
  POST_PAGE = 15
  MAX_FILES = 5
  MAX_FILE = 25.megabytes
  MAX_INLINE = 3.megabytes
  MAX_INLINE_TOTAL = 3.5.megabytes

  before_action :find_thread, except: [:index, :summary]

  def index
    return render(json: { payload: [] }) unless my_link

    scope = my_link.threads.where(kind: params[:kind] == 'channel' ? 'channel' : 'chat')
    scope = scope.where(channel_id: my_link.channel_list.pluck('channel_id')) if params[:kind] == 'channel'
    threads = scope.order(Arel.sql('last_message_at DESC NULLS LAST')).limit(200)
    render json: { payload: threads.map { |thread| json.thread(thread) } }
  end

  def summary
    link = my_link
    channels = link ? link.threads.channels.where(channel_id: link.channel_list.pluck('channel_id')) : nil
    render json: {
      connected: link.present? && link.status != 'disconnected', status: link&.status, channel_view: link&.channel_view,
      unread_chats: link ? link.threads.chats.sum(:unread_count) : 0, unread_channels: channels ? channels.sum(:unread_count) : 0,
      mentions: link ? link.threads.chats.sum(:mention_count) + channels.sum(:mention_count) : 0,
      has_threads: link.present? && link.threads.exists?
    }
  end

  def show
    render json: json.thread(@thread)
  end

  def messages
    @thread.channel? && params[:mode] != 'flat' ? render_posts : render_chat
  end

  def send_message
    return render_error('not_connected', :unprocessable_entity) unless my_link.status == 'active'

    files = Array(params[:attachments]).first(MAX_FILES)
    return render_error('file_too_big', :unprocessable_entity) if files.any? { |file| file.size > MAX_FILE }
    return render_error('empty', :unprocessable_entity) if params[:content].blank? && files.empty?

    quote = quoted_message
    return render_error('reply_to', :unprocessable_entity) if quote == :missing || reply_target == :missing

    inline, uploads = split_files(files)
    message = build_message(quote)
    message.attachments = uploads.map { |file| ::Outsider::Teams::Graph::Files.new(my_link).upload(@thread, file) } +
                          inline.map { |file| { 'kind' => 'image', 'name' => file.original_filename, 'size' => file.size, 'pending' => true } }
    message.save!
    deliver(message, inline)
    render json: json.message(message.reload), status: :created
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error("upload_failed:#{e.message}", :bad_gateway)
  end

  def retry
    message = @thread.messages.find_by!(id: params[:message_id], mine: true, status: 'failed')
    return render_error('resend', :unprocessable_entity) if Array(message.attachments).any? { |item| item['pending'] }

    message.update!(status: 'sending', error: nil)
    ::Outsider::Teams::Graph::SendJob.perform_later(message.id)
    render json: json.message(message)
  end

  def preview
    message = @thread.messages.find(params[:message_id])
    index = params[:index].to_i
    return render_error('not_found', :not_found) unless Array(message.attachments)[index]

    details = preview_of(message, index, message.attachments[index])
    shown = json.attachments(message)[index]
    render json: shown.slice(:name, :extension, :size, :download_url, :edit_url).merge(details)
  end

  def members
    refresh_chat_members if @thread.kind == 'chat'
    people = Array(@thread.members).select { |member| member['id'].present? && member['name'].present? && member['id'] != my_link.ms_user_id }
    render json: { payload: people.uniq { |member| member['id'] }.sort_by { |member| member['name'].downcase }.map { |m| m.slice('id', 'name') } }
  end

  def react
    return render_error('not_connected', :unprocessable_entity) unless my_link.status == 'active'

    message = @thread.messages.find(params[:message_id])
    emoji = params[:emoji].to_s.strip.first(16)
    return render_error('reaction', :unprocessable_entity) if emoji.blank? || message.graph_id.blank? || message.deleted_at

    ::Outsider::Teams::Graph::Reactions.new(my_link, message).apply!(emoji, on: ActiveModel::Type::Boolean.new.cast(params[:on]))
    render json: json.message(message.reload)
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error("reaction_failed:#{e.message}", :bad_gateway)
  end

  def mentions
    items = @thread.messages.where(mentions_me: true, deleted_at: nil, sent_at: MENTION_DAYS.days.ago..)
                   .order(sent_at: :desc, id: :desc).limit(MAX_MENTIONS).pluck(:id, :sent_at, :sender_name).reverse
    render json: { payload: items.map { |id, sent_at, sender| { id: id, sent_at: sent_at.iso8601, sender_name: sender } } }
  end

  def read
    @thread.update!(unread_count: 0, mention_count: 0, last_read_at: Time.current)
    ::Outsider::Teams::Graph::Notifier.changed(my_link)
    head :no_content
  end

  private

  def json
    ::Outsider::Teams::Graph::Json
  end

  def my_link
    @my_link ||= ::Outsider::TeamsLink.find_by(account_id: Current.account.id, user_id: Current.user.id)
  end

  def find_thread
    return render_error('not_connected', :not_found) unless my_link

    @thread = my_link.threads.find(params[:id])
  end

  # citação: a mensagem escolhida no Chatwoot (precisa já estar no Teams)
  def quoted_message
    return nil if params[:quote_id].blank?

    quoted = @thread.messages.find_by(id: params[:quote_id])
    return :missing unless quoted&.graph_id

    { 'graph_id' => quoted.graph_id, 'sender' => quoted.mine ? my_link.display_name.to_s : quoted.sender_name.to_s,
      'text' => summary_of(quoted),
      'message_id' => quoted.id }
  end

  # no canal: resposta dentro da publicação (a publicação da mensagem citada, ou a escolhida)
  def reply_target
    return nil unless @thread.channel?

    target = params[:reply_to_graph_id].presence
    return nil unless target

    @thread.messages.exists?(graph_id: target) ? target : :missing
  end

  def build_message(quote)
    reply_to = reply_target
    @thread.messages.new(mine: true, sender_name: my_link.display_name || Current.user.name, sender_ms_id: my_link.ms_user_id,
                         content: params[:content].to_s.strip.first(20_000).presence, reply_to_graph_id: reply_to, quote: quote,
                         subject: reply_to || !@thread.channel? ? nil : params[:subject].to_s.strip.first(250).presence,
                         status: 'sending', sent_at: Time.current)
  end

  # imagens pequenas vão dentro da mensagem (como colar no Teams); o resto vai para o OneDrive/SharePoint
  def split_files(files)
    total = 0
    files.partition do |file|
      image = file.content_type.to_s.start_with?('image/') && file.size <= MAX_INLINE && total + file.size <= MAX_INLINE_TOTAL
      total += file.size if image
      image
    end
  end

  # com imagem dentro da mensagem, manda já (os bytes não ficam guardados); sem, vai pela fila (tenta de novo sozinho)
  def deliver(message, inline)
    return ::Outsider::Teams::Graph::SendJob.perform_later(message.id) if inline.empty?

    images = inline.map do |file|
      file.rewind
      { body: file.read, content_type: file.content_type }
    end
    ::Outsider::Teams::Graph::Outbound.new(message).perform(inline: images)
  end

  def preview_of(message, index, attachment)
    files = ::Outsider::Teams::Graph::Files
    return { kind: 'image', view_url: files.media_url(message, index, 'image') } if attachment['kind'] == 'image'

    resolved = files.new(my_link).resolve!(message, index)
    url = files.new(my_link).preview_url(resolved)
    url ? { kind: 'preview', view_url: url } : { kind: 'none', reason: 'unsupported' }
  rescue ::Outsider::Teams::Graph::Client::Error
    { kind: 'none', reason: 'load' }
  end

  def refresh_chat_members
    return if @thread.updated_at > 10.minutes.ago && Array(@thread.members).any?

    data = ::Outsider::Teams::Graph::Client.new(my_link).get("/chats/#{::Outsider::Teams::Graph::Client.enc(@thread.chat_id)}/members")
    members = Array(data['value']).map { |member| { 'id' => member['userId'], 'name' => member['displayName'] } }
    @thread.update!(members: members.first(200)) if members.any?
  rescue ::Outsider::Teams::Graph::Client::Error
    nil
  end

  def render_chat
    scope = @thread.messages.order(sent_at: :desc, id: :desc)
    scope = scope.where(sent_at: ...before_time) if before_time
    items = scope.limit(CHAT_PAGE).to_a.reverse
    payload = items.map { |message| json.message(message) }
    add_post_quotes(payload) if @thread.channel?
    render json: { payload: payload, more: items.size == CHAT_PAGE }
  end

  # canal em sequência: a resposta sem citação mostra a publicação a que responde
  def add_post_quotes(payload)
    roots = @thread.messages.where(graph_id: payload.filter_map { |item| item[:reply_to_graph_id] }.uniq).index_by(&:graph_id)
    payload.each do |item|
      root = roots[item[:reply_to_graph_id]]
      next if item[:quote].present? || root.nil?

      item[:quote] = { 'graph_id' => root.graph_id, 'sender' => root.mine ? 'Você' : root.sender_name.to_s, 'post' => true,
                       'text' => summary_of(root), 'message_id' => root.id }
    end
  end

  def summary_of(message)
    (message.subject.presence || message.content.presence || Array(message.attachments).first.to_h['name']).to_s.squish.first(300)
  end

  # publicações do canal (mais novas por último) com todas as respostas de cada uma
  def render_posts
    scope = @thread.messages.posts.order(sent_at: :desc, id: :desc)
    scope = scope.where(sent_at: ...before_time) if before_time
    posts = scope.limit(POST_PAGE).to_a.reverse
    replies = @thread.messages.where(reply_to_graph_id: posts.filter_map(&:graph_id)).order(:sent_at).group_by(&:reply_to_graph_id)
    render json: {
      payload: posts.map { |post| json.message(post).merge(replies: Array(replies[post.graph_id]).map { |reply| json.message(reply) }) },
      more: posts.size == POST_PAGE
    }
  end

  def before_time
    return @before_time if defined?(@before_time)

    @before_time = params[:before].present? ? @thread.messages.find_by(id: params[:before])&.sent_at : nil
  end

  def render_error(message, status)
    render json: { error: message.to_s.split(':').first, message: message.to_s }, status: status
  end
end
