# OUTSIDER: e-mail do orçamento do ERP pelo servidor de e-mail do Chatwoot. Marca o envio como entregue ao servidor ou
# como falha, com o motivo (aparece no histórico do orçamento).
class Outsider::Erp::BudgetMailJob < ApplicationJob
  queue_as :mailers

  def perform(send_id, subject, body)
    record = Outsider::Erp::BudgetSend.find_by(id: send_id)
    return unless record&.pending?

    begin
      Outsider::Erp::BudgetMailer.budget(record, subject, body).deliver_now
      record.update!(status: :delivered)
    rescue StandardError => e
      record.update!(status: :failed, error: e.message.to_s.first(255))
    end
  end
end
