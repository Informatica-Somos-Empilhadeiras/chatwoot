# OUTSIDER: a situação de uma mensagem do Chatwoot pelo que a Evolution guardou das mensagens do WhatsApp
# dela (ver Outsider::DeliveryCheck). Em MessageUpdate ficam os avisos do WhatsApp: SERVER_ACK (saiu),
# DELIVERY_ACK (chegou no celular), READ ou PLAYED (lida ou ouvida) e ERROR (o WhatsApp recusou).
module Outsider::DeliveryStatus
  RANK = { 'sent' => 0, 'delivered' => 1, 'read' => 2 }.freeze

  module_function

  # 'sent', 'delivered', 'read' ou 'failed'. Não volta atrás (a lida não vira entregue); com vários anexos,
  # vale o mais atrasado; sem nenhuma mensagem do WhatsApp para olhar, a enviada continua como está.
  def of(message, records)
    statuses = records.map { |record| of_record(record) }
    return 'failed' if statuses.include?('failed')

    whatsapp = statuses.min_by { |status| RANK[status] } || 'sent'
    message.failed? ? whatsapp : [message.status, whatsapp].max_by { |status| RANK[status] }
  end

  def of_record(record)
    updates = Array(record['MessageUpdate']).pluck('status')
    return 'read' if updates.intersect?(%w[READ PLAYED])
    return 'delivered' if updates.include?('DELIVERY_ACK')

    updates.include?('ERROR') ? 'failed' : 'sent'
  end
end
