# OUTSIDER: o técnico e a OS de um pedido de venda do ERP, informados no chat (Outsider::Erp::SaleAttributor). O pedido
# do ERP não muda: isto é uma anotação interna, usada pelo relatório de desempenho dos técnicos
# (Outsider::Erp::TechnicianReport), que só conta o pedido depois de faturado.
# lines: [{ 'os', 'parte' (% do valor faturado do pedido; somam 100), 'tecnico_codigo', 'tecnico' }].
class Outsider::Erp::SaleAttribution < ApplicationRecord
  self.table_name = 'outsider_erp_sale_attributions'

  belongs_to :account
  belongs_to :user, optional: true

  validates :company, presence: true, format: { with: Outsider::Erp::Sql::IDENT }
  validates :order_number, numericality: { only_integer: true, greater_than: 0 }

  def os_numbers = lines.map { |line| line['os'].to_i }
end
