# OUTSIDER: avisos do próprio Chatwoot que continuam valendo no push novo: conversa atribuída a mim e citação (@) em nota
# privada. As mensagens de cliente vêm por customer_message.rb (não repete aviso da mesma mensagem).
class Outsider::Push::ChatwootNotice
  TYPES = %w[conversation_assignment conversation_mention].freeze

  def initialize(notification)
    @notification = notification
    @user = notification.user
    @account = notification.account
    @conversation = notification.primary_actor
  end

  def perform
    return 0 unless TYPES.include?(@notification.notification_type) && @conversation.is_a?(Conversation)
    return 0 unless Outsider::PushSetting.wants?(@user, @account, 'chatwoot')

    Outsider::Push::Sender.new(@user).deliver(payload)
  end

  private

  def mention?
    @notification.notification_type == 'conversation_mention'
  end

  def title
    contact = @conversation.contact&.name.presence || 'Cliente'
    return "#{@notification.secondary_actor.try(:sender)&.name || 'Alguém'} · nota em #{contact}" if mention?

    "#{contact} · #{@conversation.inbox.name}"
  end

  def body
    hide = Outsider::PushSetting.wants?(@user, @account, 'hide_content')
    if mention?
      note = @notification.secondary_actor
      return 'Citou você numa nota privada' if hide || !note.is_a?(Message)

      return "Citou você: #{Outsider::Push::Text.of_message(note).gsub(/\[(@[^\]]+)\]\([^)]*\)/, '\1')}"
    end
    last = @conversation.messages.incoming.last
    return 'Conversa atribuída a você' if hide || last.nil?

    "Atribuída a você · #{Outsider::Push::Text.of_message(last)}"
  end

  def payload
    url = "#{Outsider::Push.site}/app/accounts/#{@account.id}/conversations/#{@conversation.display_id}"
    Outsider::Push.payload(
      kind: 'chatwoot', title: title, body: body, url: url, tag: "c-#{@conversation.id}",
      icon: @conversation.contact&.avatar_url.presence,
      read: Outsider::Push.read_token({ 'u' => @user.id, 'c' => @conversation.id })
    )
  end
end
