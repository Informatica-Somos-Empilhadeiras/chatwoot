# OUTSIDER: envio de uma proposta por WhatsApp ou e-mail (Entrega 15). O PDF enviado fica ligado aqui e à
# mensagem da conversa do Chatwoot, as duas apontando para o mesmo arquivo (um blob do Active Storage).
class Outsider::Crm::ProposalSend < ApplicationRecord
  include Outsider::Crm::AccountScoped

  belongs_to :proposal, class_name: 'Outsider::Crm::Proposal'
  belongs_to :user, optional: true

  has_one_attached :document

  enum :channel, { whatsapp: 0, email: 1 }, validate: true
  enum :status, { pending: 0, delivered: 1, failed: 2 }, validate: true

  validates_same_account :proposal
end
