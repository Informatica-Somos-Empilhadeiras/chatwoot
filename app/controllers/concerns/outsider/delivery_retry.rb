# OUTSIDER: "Tentar de novo" na mensagem que falhou numa caixa da Evolution. O Chatwoot só trocava a falha
# por ✓, sem mandar nada: a Evolution só envia no webhook de mensagem nova. Agora a mensagem vai de novo
# para a Evolution e volta para a conferência (Outsider::DeliveryCheck.resend).
# Encaixado no controller de mensagens por config/initializers/outsider_message_delivery.rb.
module Outsider::DeliveryRetry
  def retry
    super
    Outsider::DeliveryCheck.resend(message) unless performed?
  end
end
