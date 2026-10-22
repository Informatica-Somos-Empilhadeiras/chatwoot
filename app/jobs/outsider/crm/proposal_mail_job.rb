# OUTSIDER: e-mail da proposta pelo servidor de e-mail do Chatwoot, para conta sem caixa de e-mail.
# Marca o envio como entregue ao servidor ou como falha, com o motivo (aparece no histórico da proposta).
class Outsider::Crm::ProposalMailJob < ApplicationJob
  queue_as :mailers

  def perform(send_id, subject, body)
    record = Outsider::Crm::ProposalSend.find_by(id: send_id)
    return unless record&.pending?

    begin
      Outsider::Crm::ProposalMailer.proposal(record, subject, body).deliver_now
      record.update!(status: :delivered)
    rescue StandardError => e
      record.update!(status: :failed, error: e.message.to_s.first(255))
    end
  end
end
