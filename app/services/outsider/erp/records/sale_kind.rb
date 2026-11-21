# OUTSIDER: lista de pedidos de venda do ERP (tabela pedido), todo o histórico, só para ver. A pessoa da linha é o
# vendedor. Sem coluna de situação no banco da unidade, ela sai da nota fiscal e do "fechado" do pedido. As visões são
# as próprias situações que aparecem (status:<valor>), montadas a partir das contagens.
class Outsider::Erp::Records::SaleKind < Outsider::Erp::Records::Kind
  S = Outsider::Erp::Sql

  def table = 'pedido'
  def person = :pessoa_codigo
  def status_views? = true

  def columns
    {
      numero: %w[CodigoPedido], data: %w[PedidoData], status: %w[Status Situacao], total: %w[total Total],
      cliente_codigo: %w[CodigoCliente], pessoa_codigo: %w[Vendedor], orcamento: %w[orcamento Orcamento],
      nota: %w[NotaFiscal], fechado: %w[fechado Fechado]
    }
  end

  def status_sql(picked)
    return super if picked[:status]

    nota = picked[:nota] ? "IFNULL(O.#{S.column(picked[:nota])}, 0) > 0" : '0'
    fechado = picked[:fechado] ? "IFNULL(O.#{S.column(picked[:fechado])}, 0) <> 0" : '0'
    "(CASE WHEN #{nota} THEN 'FATURADO' WHEN #{fechado} THEN 'FECHADO' ELSE 'ABERTO' END)"
  end
end
