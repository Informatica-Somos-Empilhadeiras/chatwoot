# OUTSIDER: lista de contratos do ERP (tabela contrato): locação, manutenção e prestação de serviço, todo o histórico, só
# para ver. A pessoa da linha é o vendedor. "Vencendo" = ativo com término nos próximos 30 dias (ou já vencido e ainda
# ativo). Cada linha conta as máquinas (itens) do contrato.
class Outsider::Erp::Records::ContractKind < Outsider::Erp::Records::Kind
  S = Outsider::Erp::Sql

  def table = 'contrato'
  def person = :pessoa_codigo
  def default_view = 'active'
  def date_keys = %i[data inicio termino]
  def dimensions = { tipo: { column: :tipo } }
  def extra_sorts = { 'termino' => 'X.termino' }

  def columns
    {
      numero: %w[CodigoContrato], data: %w[DataEmissao], status: %w[Status], total: %w[Total], cliente_codigo: %w[CodigoCliente],
      pessoa_codigo: %w[CodigoVendedor], tipo: %w[TipoContratos], inicio: %w[DataInicio], termino: %w[DataTermino],
      periodicidade: %w[periodicidadeContrato], parcela: %w[Vrparcelas]
    }
  end

  def views
    [
      { key: 'active', status_in: ['ATIVO'] }, { key: 'expiring', late: true }, { key: 'concluded', status_in: ['CONCLUÍDO'] },
      { key: 'canceled', status_in: ['CANCELADO'] }, { key: 'all' }
    ]
  end

  def late_sql
    "(X.status = 'ATIVO' AND X.termino IS NOT NULL AND X.termino <= DATE_ADD(CURDATE(), INTERVAL 30 DAY))"
  end

  def computed(company, schema)
    return ['NULL AS maquinas'] unless schema.pick(company, 'detalhecontrato', %w[CodigoContrato])

    ["(SELECT COUNT(*) FROM #{S.ident(company)}.detalhecontrato D WHERE D.`CodigoContrato` = O.`CodigoContrato`) AS maquinas"]
  end
end
