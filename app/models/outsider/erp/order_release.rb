# OUTSIDER: uma liberação de OS para a separação do estoque feita pelo chat (Outsider::Erp::Orders::Releaser). A
# liberação em si fica no ERP; aqui só quem liberou, porque o Mais Prático não guarda.
class Outsider::Erp::OrderRelease < ApplicationRecord
  self.table_name = 'outsider_erp_order_releases'

  belongs_to :account
  belongs_to :user, optional: true

  validates :company, presence: true, format: { with: Outsider::Erp::Sql::IDENT }
  validates :order_number, numericality: { only_integer: true, greater_than: 0 }

  scope :for_order, ->(company, number) { where(company: company.to_s, order_number: number.to_i) }
end
