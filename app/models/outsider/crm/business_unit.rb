# OUTSIDER: empresa ou marca do grupo (ex.: Somos Locação, Seminovos). Cada uma tem seus
# pipelines e seus membros; o encaminhamento leva a oportunidade de uma unidade para outra.
class Outsider::Crm::BusinessUnit < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account

  has_many :members, class_name: 'Outsider::Crm::BusinessUnitMember', dependent: :destroy
  has_many :pipelines, class_name: 'Outsider::Crm::Pipeline', dependent: :restrict_with_error
  has_many :opportunities, class_name: 'Outsider::Crm::Opportunity', dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :account_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
end
