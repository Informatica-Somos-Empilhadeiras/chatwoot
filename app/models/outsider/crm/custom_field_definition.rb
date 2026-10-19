# OUTSIDER: campo personalizado das oportunidades. Os valores ficam em
# outsider_crm_opportunities.custom_fields, validados por estas definições.
class Outsider::Crm::CustomFieldDefinition < ApplicationRecord
  include Outsider::Crm::AccountScoped

  enum field_type: { text: 0, number: 1, currency: 2, date: 3, list: 4, checkbox: 5 }

  validates :key, presence: true, uniqueness: { scope: :account_id }, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :label, presence: true, length: { maximum: 255 }
  validate :list_has_options

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  private

  def list_has_options
    errors.add(:options, :blank) if list? && Array(options).empty?
  end
end
