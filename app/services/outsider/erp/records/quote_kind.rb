# OUTSIDER: lista de orçamentos do ERP (tabela orcamento), todo o histórico. A pessoa da linha é o vendedor.
class Outsider::Erp::Records::QuoteKind < Outsider::Erp::Records::Kind
  def table = 'orcamento'
  def person = :pessoa_codigo

  def columns
    {
      numero: %w[codigoorcamento CodigoOrcamento], data: %w[orcamentoData DataCadastro], status: %w[Status],
      total: %w[total Total], cliente_codigo: %w[CodigoCliente], pessoa_codigo: %w[Vendedor], os: %w[OrdemServico],
      chat: %w[CodigoIntegracaoMobile]
    }
  end

  def views
    [
      { key: 'all' }, { key: 'negotiation', status_in: ['NEGOCIAÇÃO'] }, { key: 'closed', status_in: ['FECHADO'] },
      { key: 'lost', status_in: %w[CANCELADO PERDIDO] }, { key: 'mine', mine: true }
    ]
  end
end
