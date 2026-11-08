# OUTSIDER: aviso de mensagem de cliente (WhatsApp e os outros canais de atendimento).
#   Conversa com responsável: só o responsável. Sem responsável: todos os agentes da caixa, até alguém assumir.
#   Grupos do WhatsApp (@g.us) seguem as mesmas regras, se a pessoa deixou "Grupos do WhatsApp" ligado.
#   Não avisa: nota privada, mensagem que saiu da empresa, conversa com o robô (pendente) e conversa silenciada.
class Outsider::Push::CustomerMessage
  WHATSAPP_CHANNELS = %w[Channel::Whatsapp Channel::Api].freeze

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
  end

  def perform
    return 0 unless notify?

    recipients.sum { |user| Outsider::Push::Sender.new(user).deliver(payload_for(user)) }
  end

  def recipients
    group = @conversation.contact&.identifier.to_s.end_with?('@g.us')
    people = if @conversation.assignee
               [@conversation.assignee].select { |user| wants?(user, 'wa_assigned') }
             else
               @conversation.inbox.members.to_a.select { |user| wants?(user, 'wa_unassigned') }
             end
    people = people.select { |user| wants?(user, 'wa_groups') } if group
    people.select { |user| member?(user) && user.notification_subscriptions.browser_push.exists? }.uniq
  end

  private

  def notify?
    @message.incoming? && !@message.private? && !@conversation.pending? && !@conversation.muted?
  end

  def wants?(user, key)
    Outsider::PushSetting.wants?(user, @account, key)
  end

  def member?(user)
    user.account_users.exists?(account_id: @account.id)
  end

  def sender_name
    @message.sender.try(:name).presence || @conversation.contact&.name.presence || 'Cliente'
  end

  def title
    contact = @conversation.contact&.name.presence || sender_name
    "#{contact} · #{@conversation.inbox.name}"
  end

  def body(user)
    return "Nova mensagem de #{sender_name}" if Outsider::PushSetting.wants?(user, @account, 'hide_content')

    text = Outsider::Push::Text.of_message(@message)
    # no grupo, quem escreveu vai na frente do texto
    group = @conversation.contact&.identifier.to_s.end_with?('@g.us')
    group && sender_name != @conversation.contact&.name ? "#{sender_name}: #{text}" : text
  end

  def kind
    WHATSAPP_CHANNELS.include?(@conversation.inbox.channel_type) ? 'whatsapp' : 'chatwoot'
  end

  def payload_for(user)
    url = "#{Outsider::Push.site}/app/accounts/#{@account.id}/conversations/#{@conversation.display_id}"
    Outsider::Push.payload(
      kind: kind, title: title, body: body(user), url: url, tag: "c-#{@conversation.id}",
      icon: @conversation.contact&.avatar_url.presence,
      read: Outsider::Push.read_token({ 'u' => user.id, 'c' => @conversation.id })
    )
  end
end
