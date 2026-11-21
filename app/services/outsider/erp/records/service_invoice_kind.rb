# OUTSIDER: lista de notas fiscais de serviço (NFS-e, tabela notafiscalservico) do ERP, todo o histórico, só para ver.
# A chave é a sequência interna (SeqNFSe); o número da prefeitura (CodigoNFS) vem em "rotulo" e também entra na busca
# por número. O destinatário (CodigoDestinatario) é o cliente; a pessoa da linha é o vendedor.
class Outsider::Erp::Records::ServiceInvoiceKind < Outsider::Erp::Records::Kind
  def table = 'notafiscalservico'
  def person = :pessoa_codigo
  def number_keys = %i[numero rotulo]
  def status_views? = true

  def columns
    {
      numero: %w[SeqNFSe], data: %w[Emissao], status: %w[Status], total: %w[TotalNF Total], cliente_codigo: %w[CodigoDestinatario],
      pessoa_codigo: %w[Vendedor], pedido: %w[Pedido], rotulo: %w[CodigoNFS]
    }
  end
end
