# OUTSIDER: tarefa de uma oportunidade (ligação, visita, proposta...). Criar e concluir aparecem
# na linha do tempo do negócio; adiar, editar e apagar ficam na auditoria.
class Outsider::Crm::Task < ApplicationRecord
  include Outsider::Crm::AccountScoped
  include Outsider::Crm::LiveBroadcast

  audited associated_with: :account

  belongs_to :opportunity, class_name: 'Outsider::Crm::Opportunity'
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :completed_by, class_name: 'User', optional: true

  enum :kind, { todo: 0, call: 1, meeting: 2, visit: 3, proposal: 4, follow_up: 5 }, validate: true

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5000 }
  validates_same_account :opportunity
  validate :assignee_in_account

  scope :pending, -> { where(completed_at: nil) }
  scope :overdue, -> { pending.where(due_at: ...Time.current) }

  after_create :log_created
  after_update :log_completed, if: -> { saved_change_to_completed_at? && completed? }

  def completed?
    completed_at.present?
  end

  def overdue?
    !completed? && due_at.present? && due_at < Time.current
  end

  # Marca ou desmarca como feita, guardando quem concluiu
  def complete!(user, done: true)
    update!(completed_at: done ? Time.current : nil, completed_by: done ? user : nil)
  end

  private

  def assignee_in_account
    return if assignee_id.blank? || account.blank?

    errors.add(:assignee, :invalid) unless account.account_users.exists?(user_id: assignee_id)
  end

  def log_created
    log_activity(:task_created, title: title, kind: kind, due_at: due_at&.iso8601, assignee: assignee&.name)
  end

  def log_completed
    log_activity(:task_completed, title: title, kind: kind)
  end

  def log_activity(kind, **metadata)
    opportunity.activities.create!(account_id: account_id, user: Current.user, kind: kind,
                                   metadata: metadata.merge(task_id: id).compact)
  end
end
