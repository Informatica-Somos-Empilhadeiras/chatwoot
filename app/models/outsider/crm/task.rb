# OUTSIDER: tarefa de uma oportunidade (ligação, visita, proposta...).
class Outsider::Crm::Task < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account

  belongs_to :opportunity, class_name: 'Outsider::Crm::Opportunity'
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :completed_by, class_name: 'User', optional: true

  enum :kind, { todo: 0, call: 1, meeting: 2, visit: 3, proposal: 4, follow_up: 5 }, validate: true

  validates :title, presence: true, length: { maximum: 255 }
  validates_same_account :opportunity

  scope :pending, -> { where(completed_at: nil) }
  scope :overdue, -> { pending.where(due_at: ...Time.current) }
end
