# OUTSIDER: item da proposta. Pode vir do catálogo (product, com o retrato das características em details)
# ou ser livre. Total = quantidade x valor unitário - desconto (em R$, como nas propostas da Somos).
class Outsider::Crm::ProposalItem < ApplicationRecord
  include Outsider::Crm::AccountScoped

  belongs_to :proposal, class_name: 'Outsider::Crm::Proposal', inverse_of: :items
  belongs_to :product, class_name: 'Outsider::Crm::Product', optional: true

  validates :description, presence: true, length: { maximum: 500 }
  validates :quantity, numericality: { greater_than: 0, less_than: 1_000_000 }
  validates :unit_price_cents, :discount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates_same_account :proposal, :product
  validate :discount_not_above_gross

  before_validation :apply_total

  def gross_cents
    (quantity.to_d * unit_price_cents).round.to_i
  end

  # Imagem que a proposta mostra: a do produto do catálogo (guardada uma vez só)
  def image
    product&.image&.attached? ? product.image : nil
  end

  def apply_total
    self.total_cents = [gross_cents - discount_cents.to_i, 0].max
  end

  private

  def discount_not_above_gross
    errors.add(:discount_cents, :invalid) if discount_cents.to_i > gross_cents
  end
end
