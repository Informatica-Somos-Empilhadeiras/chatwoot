# OUTSIDER: aviso (push) para quem mandou a mensagem que a conferência de entrega deu como falha (ver
# Outsider::DeliveryCheck). O balão fica vermelho na conversa, mas a pessoa pode já estar em outra. A mensagem
# do bot ou de uma integração avisa o responsável pela conversa.
class Outsider::Push::UndeliveredMessage
  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
  end

  def perform
    return 0 unless Outsider::Push.enabled? && user && Outsider::PushSetting.wants?(user, @account, 'chatwoot')

    Outsider::Push::Sender.new(user).deliver(payload)
  end

  private

  def user
    @user ||= @message.sender.is_a?(User) ? @message.sender : @conversation.assignee
  end

  def body
    return @message.external_error if Outsider::PushSetting.wants?(user, @account, 'hide_content')

    "“#{Outsider::Push::Text.of_message(@message).truncate(50)}” · #{@message.external_error}"
  end

  def payload
    contact = @conversation.contact&.name.presence || 'Cliente'
    Outsider::Push.payload(
      kind: 'whatsapp', title: "⚠️ Mensagem não enviada · #{contact}", body: body, tag: "undelivered-#{@conversation.id}",
      url: "#{Outsider::Push.site}/app/accounts/#{@account.id}/conversations/#{@conversation.display_id}",
      person: contact, photo: @conversation.contact&.avatar_url.presence
    )
  end
end
