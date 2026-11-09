# OUTSIDER: mensagem do Teams entrando na área Teams de um colaborador. O aviso da Microsoft só diz onde está a mensagem
# (resource); aqui ela é buscada no Graph com o token da pessoa, então o conteúdo vem sempre da Microsoft.
#   chats('19:..')/messages('..')                               -> chat (1:1, grupo, reunião)
#   teams('..')/channels('19:..')/messages('..')[/replies('..')] -> canal (publicação ou resposta)
# Mensagem escrita pela própria pessoa (no Teams ou pelo Chatwoot) fica como "minha"; a que o Chatwoot mandou já tem o
# id do Teams e não entra duas vezes. Edição e exclusão no Teams atualizam a mensagem. Arquivos (OneDrive/SharePoint) e
# imagens coladas não são baixados: fica só nome e endereço (Outsider::Teams::Graph::Files mostra na hora).
# Reações (👍 ❤️ ...) ficam em reactions e mudam quando o Teams avisa que a mensagem foi alterada.
# Citação (responder citando no Teams) fica em quote; menção à pessoa (@ela, ou @canal/@equipe no canal) em mentions_me.
# quiet: mensagem antiga (Outsider::Teams::Graph::History): entra sem push, sem aviso ao vivo e sem contar como não lida.
class Outsider::Teams::Graph::Inbound
  CHAT = %r{chats\('([^']+)'\)/messages\('([^']+)'\)}
  CHANNEL = %r{teams\('([^']+)'\)/channels\('([^']+)'\)/messages\('([^']+)'\)(?:/replies\('([^']+)'\))?}
  MAX_IMAGES = 10
  MAX_FILES = 20
  REPLY_QUOTE = %r{<blockquote[^>]*itemtype="http://schema\.skype\.com/Reply"[^>]*>.*?</blockquote>}im

  def self.parse(resource)
    resource = resource.to_s
    if (match = resource.match(CHANNEL))
      { kind: 'channel', team_id: match[1], channel_id: match[2], message_id: match[4] || match[3], parent_id: match[4] && match[3] }
    elsif (match = resource.match(CHAT))
      { kind: 'chat', chat_id: match[1], message_id: match[2] }
    end
  end

  def self.text_of(body)
    content = body.to_h['content'].to_s
    return content.strip if body.to_h['contentType'] == 'text'

    html = content.gsub(REPLY_QUOTE, '')
    html = html.gsub(%r{<emoji[^>]*\balt="([^"]*)"[^>]*>(?:\s*</emoji>)?}i) { Regexp.last_match(1) }
    html = html.gsub(%r{<at\b[^>]*>(.*?)</at>}im) { "@#{Regexp.last_match(1)}" }
    html = html.gsub(%r{<br\s*/?>|</p>|</div>|</li>|</h\d>}i, "\n")
    CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(html)).tr("\u00A0", ' ').gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
  end

  def initialize(link, ref, change_type = 'created', quiet: false)
    @link = link
    @ref = ref
    @change_type = change_type.to_s
    @quiet = quiet
    @client = Outsider::Teams::Graph::Client.new(link)
  end

  # data: a mensagem já lida do Graph (histórico); sem ela, busca pelo endereço do aviso
  def perform(data = nil)
    return mark_deleted if @change_type == 'deleted'

    data ||= fetch
    return if data.nil? || data['messageType'] != 'message'
    return if @quiet && data['deletedDateTime'].present?

    thread = find_or_create_thread
    message = thread.messages.find_by(graph_id: data['id'])
    return (@quiet ? message : update_existing(thread, message, data)) if message

    message = create_message(thread, data)
    touch_thread(thread, message)
    return message if @quiet

    Outsider::Teams::Graph::Notifier.message(@link, thread, message)
    # aviso novo (push): só mensagem nova de outra pessoa
    Outsider::Push::DeliverJob.perform_later('teams', message.id) if message.previously_new_record? && !message.mine
    message
  end

  private

  def fetch
    @client.get(message_path)
  rescue Outsider::Teams::Graph::Client::Error => e
    raise unless e.status == 404

    nil
  end

  def message_path
    enc = Outsider::Teams::Graph::Client.method(:enc)
    if @ref[:kind] == 'chat'
      "/chats/#{enc.call(@ref[:chat_id])}/messages/#{enc.call(@ref[:message_id])}"
    elsif @ref[:parent_id]
      "/teams/#{enc.call(@ref[:team_id])}/channels/#{enc.call(@ref[:channel_id])}/messages/#{enc.call(@ref[:parent_id])}" \
        "/replies/#{enc.call(@ref[:message_id])}"
    else
      "/teams/#{enc.call(@ref[:team_id])}/channels/#{enc.call(@ref[:channel_id])}/messages/#{enc.call(@ref[:message_id])}"
    end
  end

  def find_or_create_thread
    if @ref[:kind] == 'chat'
      @link.threads.find_by(chat_id: @ref[:chat_id]) || create_chat_thread
    else
      @link.threads.find_by(channel_id: @ref[:channel_id]) || create_channel_thread
    end
  end

  def create_chat_thread
    chat = @client.get("/chats/#{Outsider::Teams::Graph::Client.enc(@ref[:chat_id])}?$expand=members")
    members = Array(chat['members']).map { |member| { 'id' => member['userId'], 'name' => member['displayName'] } }
    @link.threads.create!(kind: 'chat', chat_id: @ref[:chat_id], chat_type: chat['chatType'], members: members.first(50),
                          title: chat_title(chat, members))
  rescue ActiveRecord::RecordNotUnique
    @link.threads.find_by!(chat_id: @ref[:chat_id])
  end

  def chat_title(chat, members)
    return chat['topic'] if chat['topic'].present?

    others = members.reject { |member| member['id'] == @link.ms_user_id }.filter_map { |member| member['name'].presence }
    return others.first.to_s if chat['chatType'] == 'oneOnOne'

    names = others.first(3).join(', ')
    others.size > 3 ? "#{names} +#{others.size - 3}" : names
  end

  def create_channel_thread
    chosen = @link.channel_list.find { |channel| channel['channel_id'] == @ref[:channel_id] } || {}
    @link.threads.create!(kind: 'channel', team_id: @ref[:team_id], channel_id: @ref[:channel_id],
                          team_name: chosen['team_name'], title: chosen['channel_name'].presence || 'Canal')
  rescue ActiveRecord::RecordNotUnique
    @link.threads.find_by!(channel_id: @ref[:channel_id])
  end

  def create_message(thread, data)
    sender_id = data.dig('from', 'user', 'id')
    mine = sender_id.present? && sender_id == @link.ms_user_id
    remember_sender(thread, sender_id, sender_name(data)) if thread.channel? && !mine
    thread.messages.create!(
      graph_id: data['id'], reply_to_graph_id: thread.channel? ? data['replyToId'].presence : nil, mine: mine,
      sender_name: sender_name(data), sender_ms_id: sender_id, subject: data['subject'].presence&.first(250),
      content: self.class.text_of(data['body']), attachments: attachments(data), quote: quote(data), status: 'sent',
      reactions: Outsider::Teams::Graph::Reactions.parse(data['reactions'], thread),
      mentions_me: !mine && mentions_me?(thread, data), sent_at: Time.zone.parse(data['createdDateTime'].to_s) || Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    thread.messages.find_by!(graph_id: data['id'])
  end

  def update_existing(thread, message, data)
    deleted = data['deletedDateTime'].present?
    message.update!(content: deleted ? nil : self.class.text_of(data['body']), attachments: deleted ? [] : attachments(data),
                    edited_at: Time.zone.parse(data['lastEditedDateTime'].to_s) || message.edited_at,
                    reactions: deleted ? [] : Outsider::Teams::Graph::Reactions.parse(data['reactions'], thread),
                    deleted_at: deleted ? (Time.zone.parse(data['deletedDateTime'].to_s) || Time.current) : nil)
    Outsider::Teams::Graph::Notifier.message(@link, thread, message, action: 'updated')
    message
  end

  def mark_deleted
    thread = @ref[:kind] == 'chat' ? @link.threads.find_by(chat_id: @ref[:chat_id]) : @link.threads.find_by(channel_id: @ref[:channel_id])
    message = thread&.messages&.find_by(graph_id: @ref[:message_id])
    return unless message

    message.update!(content: nil, attachments: [], deleted_at: Time.current)
    Outsider::Teams::Graph::Notifier.message(@link, thread, message, action: 'updated')
  end

  def touch_thread(thread, message)
    return if thread.last_message_at.present? && thread.last_message_at > message.sent_at

    attributes = { last_message_at: message.sent_at, last_message_preview: preview(thread, message) }
    attributes[:unread_count] = thread.unread_count + 1 unless message.mine || @quiet
    attributes[:mention_count] = thread.mention_count + 1 if message.mentions_me && !@quiet
    thread.update!(attributes)
    @link.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def preview(thread, message)
    text = message.content.presence || attachment_preview(message.attachments)
    who = if message.mine
            'Você: '
          elsif thread.channel? || thread.chat_type != 'oneOnOne'
            "#{message.sender_name.to_s.split.first}: "
          else
            ''
          end
    "#{who}#{text.squish}".first(160)
  end

  def sender_name(data)
    data.dig('from', 'user', 'displayName').presence || data.dig('from', 'application', 'displayName').presence || 'Teams'
  end

  def attachment_preview(list)
    first = Array(list).first
    return '' unless first

    return '🖼 Imagem' if first['kind'] == 'image' && first['hosted'].present?
    return '🎤 Áudio' if first['kind'] == 'audio'

    "📎 #{first['name']}"
  end

  # arquivos do Teams (referências ao OneDrive/SharePoint) e imagens coladas na mensagem: só nome e endereço
  def attachments(data)
    files = Array(data['attachments']).filter_map do |attachment|
      url = attachment['contentUrl'].to_s
      next unless attachment['contentType'] == 'reference' && url.start_with?('https://')

      name = attachment['name'].presence || CGI.unescape(File.basename(URI.parse(url).path.to_s)).presence || 'Arquivo'
      files = Outsider::Teams::Graph::Files
      kind = if files.image?(name) then 'image'
             elsif files.audio?(name) then 'audio'
             else
               'file'
             end
      { 'kind' => kind, 'name' => name, 'url' => url,
        'source' => Outsider::Teams::Graph::Files.source(url) }
    rescue URI::InvalidURIError
      nil
    end
    (files.first(MAX_FILES) + images(data))
  end

  def images(data)
    content = data.dig('body', 'content').to_s
    urls = content.scan(/<img[^>]+src="([^"]+)"/i).flatten.map { |url| CGI.unescapeHTML(url) }
    urls.select { |url| Outsider::Teams::Graph::Client.graph_url?(url) }.uniq.first(MAX_IMAGES).each_with_index.map do |url, index|
      { 'kind' => 'image', 'name' => "imagem-#{index + 1}.png", 'hosted' => url, 'source' => 'teams' }
    end
  end

  # "Responder citando" do Teams: anexo messageReference (atual) ou o bloco Reply no texto (versões antigas)
  def quote(data)
    reference = Array(data['attachments']).find { |attachment| attachment['contentType'] == 'messageReference' }
    if reference
      content = begin
        JSON.parse(reference['content'].to_s)
      rescue JSON::ParserError
        {}
      end
      sender = content.dig('messageSender', 'user', 'displayName') || content.dig('messageSender', 'application', 'displayName')
      return { 'graph_id' => (content['messageId'] || reference['id']).to_s, 'sender' => sender.to_s,
               'text' => content['messagePreview'].to_s.squish.first(300) }
    end

    block = data.dig('body', 'content').to_s[REPLY_QUOTE]
    return nil unless block

    { 'graph_id' => block[/itemid="([^"]+)"/i, 1].to_s, 'sender' => plain(block[%r{itemprop="mri"[^>]*>(.*?)</}im, 1]),
      'text' => plain(block[%r{itemprop="preview"[^>]*>(.*?)</p>}im, 1]).first(300) }
  end

  def plain(html)
    CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(html.to_s)).squish
  end

  # @pessoa; no canal também @canal e @equipe (menção da conversa inteira)
  def mentions_me?(thread, data)
    Array(data['mentions']).any? do |mention|
      mentioned = mention['mentioned'].to_h
      mentioned.dig('user', 'id') == @link.ms_user_id || (thread.channel? && mentioned['conversation'].present?)
    end
  end

  # no canal, quem escreve entra na lista de pessoas que dá para @mencionar daqui
  def remember_sender(thread, id, name)
    return if id.blank? || Array(thread.members).any? { |member| member['id'] == id }

    thread.update_columns(members: (Array(thread.members) + [{ 'id' => id, 'name' => name }]).last(200)) # rubocop:disable Rails/SkipsModelValidations
  end
end
