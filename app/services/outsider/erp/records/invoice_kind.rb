# OUTSIDER: lista de notas fiscais de produtos (NF-e, tabela notafiscal) do ERP, todo o histórico, só para ver. A pessoa
# da linha é o vendedor. As visões são as próprias situações que aparecem (IMPRESSA, CANCELADA, INUTILIZADA...);
# TipoNota 0 = saída, 1 = entrada (devoluções e retornos).
class Outsider::Erp::Records::InvoiceKind < Outsider::Erp::Records::Kind
  def table = 'notafiscal'
  def person = :pessoa_codigo
  def search_keys = %i[natureza]
  def status_views? = true

  def columns
    {
      numero: %w[CodigoNF], data: %w[Emissao], status: %w[Status], total: %w[TotalNF total], cliente_codigo: %w[CodigoCliente],
      pessoa_codigo: %w[Vendedor], pedido: %w[Pedido], natureza: %w[Natureza], tipo: %w[TipoNota]
    }
  end
end
