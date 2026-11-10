# OUTSIDER: roda a conferência de entrega (Outsider::DeliveryCheck): a cada minuto em todas as caixas da
# Evolution e, com a caixa, logo depois de um webhook de mensagem.
# Agendado no config/initializers/outsider_message_delivery.rb.
class Outsider::DeliveryCheckJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(inbox_id = nil)
    return unless Outsider::DeliveryCheck.enabled?

    inboxes = inbox_id ? Inbox.where(id: inbox_id) : Outsider::EvolutionApi.inboxes
    inboxes.each { |inbox| Outsider::DeliveryCheck.new(inbox).perform(follow: inbox_id.nil?) }
  end
end
