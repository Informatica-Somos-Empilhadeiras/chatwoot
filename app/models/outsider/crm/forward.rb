# OUTSIDER: tentativa de levar um lead de uma unidade para outra. Guarda origem, destino,
# motivo e resultado; a oportunidade de origem continua existindo, com status forwarded.
class Outsider::Crm::Forward < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account

  belongs_to :journey, class_name: 'Outsider::Crm::Journey'
  belongs_to :from_opportunity, class_name: 'Outsider::Crm::Opportunity'
  belongs_to :to_opportunity, class_name: 'Outsider::Crm::Opportunity', optional: true
  belongs_to :from_business_unit, class_name: 'Outsider::Crm::BusinessUnit'
  belongs_to :to_business_unit, class_name: 'Outsider::Crm::BusinessUnit'
  belongs_to :reason, class_name: 'Outsider::Crm::LostReason', optional: true
  belongs_to :requested_by, class_name: 'User', optional: true
  belongs_to :decided_by, class_name: 'User', optional: true

  enum status: { pending: 0, accepted: 1, declined: 2 }

  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  validates_same_account :journey, :from_opportunity, :to_opportunity, :from_business_unit, :to_business_unit, :reason
  validate :different_units

  private

  def different_units
    errors.add(:to_business_unit, :invalid) if from_business_unit_id.present? && from_business_unit_id == to_business_unit_id
  end
end
