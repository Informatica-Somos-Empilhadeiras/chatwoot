# OUTSIDER: guarda o id do WhatsApp da mensagem respondida quando ela não existe
# no Chatwoot, como quando o contato responde ou reage a um status. O Chatwoot
# apaga esse id em ensure_in_reply_to; a página Status do WhatsApp usa ATTRIBUTE
# para contar as respostas de cada status (ver app/services/outsider/whatsapp_status_service.rb).
# Encaixado no Message por config/initializers/outsider_whatsapp_status.rb.
module Outsider::MessageReplyLink
  ATTRIBUTE = 'outsider_reply_to_external_id'.freeze

  private

  def ensure_in_reply_to
    external_id = content_attributes[:in_reply_to_external_id]
    super
    content_attributes[ATTRIBUTE] = external_id if external_id.present? && content_attributes[:in_reply_to].blank?
  end
end
