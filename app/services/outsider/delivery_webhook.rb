# OUTSIDER: o webhook que leva à Evolution uma mensagem em conferência (ver Outsider::DeliveryCheck).
# - marca a hora em que o webhook saiu (o prazo da conferência conta daí, não da criação: com a fila do
#   Sidekiq cheia o webhook pode sair minutos depois) e pede a conferência para logo em seguida;
# - a Evolution só responde depois de mandar ao WhatsApp. Se ela passar do tempo do webhook (arquivo
#   grande, WhatsApp lento), a mensagem ainda pode sair: em vez de virar falha na hora, e o agente mandar
#   de novo o que já foi, fica no relógio e a conferência decide. Os outros erros (Evolution fora do ar,
#   endereço errado) continuam virando falha na hora.
# Encaixado no Webhooks::Trigger por config/initializers/outsider_message_delivery.rb.
module Outsider::DeliveryWebhook
  def execute
    return super unless outsider_delivery?

    Outsider::DeliveryCheck.webhook_started(@payload[:id])
    super.tap { Outsider::DeliveryCheck.check_soon(@payload.dig(:inbox, :id)) }
  end

  private

  def update_message_status(error)
    super unless outsider_delivery? && error.cause.is_a?(Net::ReadTimeout)
  end

  def outsider_delivery?
    @webhook_type == :api_inbox_webhook && @payload[:event] == 'message_created' &&
      @payload[:content_attributes].to_h[Outsider::DeliveryCheck::STATE] == Outsider::DeliveryCheck::CHECKING
  end
end
