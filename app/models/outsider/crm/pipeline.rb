# OUTSIDER: funil de vendas de uma unidade, com etapas configuráveis.
class Outsider::Crm::Pipeline < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account

  belongs_to :business_unit, class_name: 'Outsider::Crm::BusinessUnit'
  has_many :stages, -> { order(:position, :id) }, class_name: 'Outsider::Crm::Stage', dependent: :destroy, inverse_of: :pipeline
  has_many :opportunities, class_name: 'Outsider::Crm::Opportunity', dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 255 }
  validates_same_account :business_unit

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def first_open_stage
    stages.find_by(kind: :open)
  end
end
