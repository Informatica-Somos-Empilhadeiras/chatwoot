# OUTSIDER: etapa de um pipeline. kind marca as etapas finais (won/lost); probability é a
# chance padrão das oportunidades na etapa.
class Outsider::Crm::Stage < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account

  belongs_to :pipeline, class_name: 'Outsider::Crm::Pipeline'
  has_many :opportunities, class_name: 'Outsider::Crm::Opportunity', dependent: :restrict_with_error

  enum kind: { open: 0, won: 1, lost: 2 }, _prefix: :kind

  validates :name, presence: true, length: { maximum: 255 }
  validates :probability, numericality: { only_integer: true, in: 0..100 }
  validates :sla_hours, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates_same_account :pipeline
end
