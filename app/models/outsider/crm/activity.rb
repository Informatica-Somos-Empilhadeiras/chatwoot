# OUTSIDER: item da linha do tempo de uma oportunidade (nota interna, mudança de etapa,
# encaminhamento...). Notas internas do CRM nunca são enviadas ao cliente.
class Outsider::Crm::Activity < ApplicationRecord
  include Outsider::Crm::AccountScoped

  belongs_to :opportunity, class_name: 'Outsider::Crm::Opportunity'
  belongs_to :user, optional: true
  belongs_to :message, optional: true

  enum :kind, { note: 0, created: 1, stage_changed: 2, status_changed: 3, owner_changed: 4,
                task_created: 5, task_completed: 6, forwarded: 7, received: 8, message_linked: 9 }, validate: true

  validates :body, presence: true, if: :note?
  validates :body, length: { maximum: 20_000 }
  validates_same_account :opportunity, :message
end
