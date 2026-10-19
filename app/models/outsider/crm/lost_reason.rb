# OUTSIDER: motivo de perda ou de encaminhamento, escolhido de uma lista configurável.
class Outsider::Crm::LostReason < ApplicationRecord
  include Outsider::Crm::AccountScoped

  enum :kind, { lost: 0, forward: 1, both: 2 }, prefix: :for, validate: true

  validates :name, presence: true, length: { maximum: 255 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
end
