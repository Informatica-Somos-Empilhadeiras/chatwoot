# OUTSIDER: item da linha do tempo de uma oportunidade (nota interna, mudança de etapa,
# encaminhamento, automação...). Notas internas do CRM ficam só aqui: nunca viram mensagem do Chatwoot e
# nunca são enviadas ao cliente. Nota apagada fica registrada na auditoria.
class Outsider::Crm::Activity < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account, on: [:destroy]

  belongs_to :opportunity, class_name: 'Outsider::Crm::Opportunity'
  belongs_to :user, optional: true
  belongs_to :message, optional: true

  enum :kind, { note: 0, created: 1, stage_changed: 2, status_changed: 3, owner_changed: 4,
                task_created: 5, task_completed: 6, forwarded: 7, received: 8, message_linked: 9,
                automation: 10, proposal: 11 }, validate: true

  validates :body, presence: true, if: :note?
  validates :body, length: { maximum: 20_000 }
  validates_same_account :opportunity, :message
end
