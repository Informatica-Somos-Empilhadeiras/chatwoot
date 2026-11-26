# OUTSIDER: o pin do WhatsApp com o local exato do agendamento da OS (Outsider::Erp::OrderScheduler), alguns segundos
# depois do texto do aviso, para chegar depois dele. Vai direto pela Evolution (Outsider::LocationSender).
class Outsider::Erp::ScheduleLocationJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, user_id, place)
    conversation = Conversation.find_by(id: conversation_id)
    user = User.find_by(id: user_id)
    return unless conversation && user

    Outsider::LocationSender.new(conversation: conversation, user: user, location: place).perform
  rescue Outsider::LocationSender::Invalid, Outsider::EvolutionApi::Error => e
    Rails.logger.info("[Outsider::Erp] pin do agendamento não enviado (conversa #{conversation_id}): #{e.message}")
  end
end
