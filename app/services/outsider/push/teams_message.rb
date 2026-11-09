# OUTSIDER: aviso de mensagem do Teams (área Teams de cada pessoa). Avisa chat 1:1, @menção (grupo ou canal) e resposta a
# publicação em que a pessoa escreveu; todas as mensagens dos chats em grupo só se ela ligar. Mensagem da própria pessoa
# ou apagada não avisa.
class Outsider::Push::TeamsMessage
  def initialize(message)
    @message = message
    @thread = message.thread
    @link = @thread.link
  end

  def perform
    user = @link.user
    return 0 if user.nil? || @link.status != 'active' || @message.mine || @message.deleted_at.present?
    return 0 unless reasons.any? { |key| Outsider::PushSetting.wants?(user, @link.account, key) }

    Outsider::Push::Sender.new(user).deliver(payload_for(user))
  end

  # por que este aviso vale: as chaves de Outsider::PushSetting::DEFAULTS
  def reasons
    found = []
    found << 'teams_mentions' if @message.mentions_me
    found << 'teams_chats' if @thread.kind == 'chat' && @thread.chat_type == 'oneOnOne'
    found << 'teams_groups' if @thread.kind == 'chat' && @thread.chat_type != 'oneOnOne'
    found << 'teams_replies' if reply_to_mine?
    found
  end

  private

  def reply_to_mine?
    return false unless @thread.kind == 'channel' && @message.reply_to_graph_id.present?

    @thread.messages.where(mine: true).exists?(['graph_id = :post OR reply_to_graph_id = :post', { post: @message.reply_to_graph_id }])
  end

  def origin
    return 'Teams (chat)' if @thread.kind == 'chat' && @thread.chat_type == 'oneOnOne'

    "Teams › #{@thread.title.presence || 'Teams'}"
  end

  def body(user)
    name = @message.sender_name.presence || 'Alguém'
    return "Nova mensagem de #{name}" if Outsider::PushSetting.wants?(user, @link.account, 'hide_content')

    text = Outsider::Push::Text.of_teams(@message)
    @message.mentions_me ? "Mencionou você: #{text}" : text
  end

  # no canal, a resposta rápida vai dentro da mesma publicação
  def post_id
    return nil unless @thread.kind == 'channel'

    @message.reply_to_graph_id.presence || @message.graph_id.presence
  end

  def payload_for(user)
    kind = @thread.kind == 'channel' ? 'channels' : 'chats'
    url = "#{Outsider::Push.site}/app/accounts/#{@link.account_id}/teams/#{kind}/#{@thread.id}"
    Outsider::Push.payload(
      kind: 'teams', title: "#{@message.sender_name.presence || 'Teams'} · #{origin}", body: body(user), url: url,
      tag: "t-#{@thread.id}", person: @message.sender_name.presence || 'Teams',
      read: Outsider::Push.read_token({ 'u' => user.id, 't' => @thread.id }),
      reply: Outsider::Push.reply_token({ 'u' => user.id, 't' => @thread.id, 'p' => post_id }.compact)
    )
  end
end
