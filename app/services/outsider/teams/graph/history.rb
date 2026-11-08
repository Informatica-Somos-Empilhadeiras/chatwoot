# OUTSIDER: traz as mensagens antigas para a área Teams da pessoa, uma vez: os chats com conversa nos últimos 90 dias
# (até 50 chats, 50 mensagens de cada) e cada canal que entra na lista (30 publicações, com as respostas). Entra em silêncio:
# sem push, sem aviso ao vivo e sem contar como não lida. Mensagem que já existe não entra de novo.
class Outsider::Teams::Graph::History
  MAX_CHATS = 50
  CHAT_MESSAGES = 50
  CHANNEL_POSTS = 30
  CHAT_DAYS = 90

  def initialize(link)
    @link = link
    @client = Outsider::Teams::Graph::Client.new(link)
  end

  def perform
    if @link.history_at.nil?
      import_chats if @link.sync_chats
      @link.update_columns(history_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
    @link.channel_list.each do |channel|
      next if channel_done?(channel)

      import_channel(channel)
      done = (Array(@link.history_channels) + [channel_key(channel)]).uniq.last(500)
      @link.update_columns(history_channels: done) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def import_chats
    chats = Array(@client.get("/me/chats?$top=#{MAX_CHATS}&$orderby=lastMessagePreview/createdDateTime%20desc" \
                              '&$expand=lastMessagePreview')['value'])
    chats.each do |chat|
      last = Time.zone.parse(chat.dig('lastMessagePreview', 'createdDateTime').to_s)
      next if last.nil? || last < CHAT_DAYS.days.ago

      import_chat(chat['id'])
    end
  end

  def import_chat(chat_id)
    messages = Array(@client.get("/chats/#{enc(chat_id)}/messages?$top=#{CHAT_MESSAGES}")['value'])
    messages.reverse_each do |data|
      quiet(kind: 'chat', chat_id: chat_id, message_id: data['id']).perform(data)
    end
  rescue Outsider::Teams::Graph::Client::Reconnect
    raise
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.warn("[outsider_teams_graph] history chat: #{e.message}")
  end

  def import_channel(channel)
    path = "/teams/#{enc(channel['team_id'])}/channels/#{enc(channel['channel_id'])}/messages?$top=#{CHANNEL_POSTS}&$expand=replies"
    posts = Array(@client.get(path)['value'])
    ref = { kind: 'channel', team_id: channel['team_id'], channel_id: channel['channel_id'] }
    posts.reverse_each do |post|
      quiet(**ref, message_id: post['id']).perform(post)
      Array(post['replies']).sort_by { |reply| reply['createdDateTime'].to_s }.each do |reply|
        quiet(**ref, message_id: reply['id'], parent_id: post['id']).perform(reply)
      end
    end
    ensure_thread(channel) if posts.empty?
  rescue Outsider::Teams::Graph::Client::Reconnect
    raise
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.warn("[outsider_teams_graph] history channel: #{e.message}")
  end

  # canal sem mensagem ainda: aparece na lista mesmo assim
  def ensure_thread(channel)
    return if @link.threads.exists?(channel_id: channel['channel_id'])

    @link.threads.create!(kind: 'channel', team_id: channel['team_id'], channel_id: channel['channel_id'],
                          team_name: channel['team_name'], title: channel['channel_name'].presence || 'Canal')
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def channel_done?(channel)
    Array(@link.history_channels).include?(channel_key(channel))
  end

  def channel_key(channel)
    "#{channel['team_id']}|#{channel['channel_id']}"
  end

  def quiet(**ref)
    Outsider::Teams::Graph::Inbound.new(@link, ref, 'created', quiet: true)
  end

  def enc(value)
    Outsider::Teams::Graph::Client.enc(value)
  end
end
