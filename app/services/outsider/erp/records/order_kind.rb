# OUTSIDER: lista de ordens de serviço do ERP (tabela os), todo o histórico. A pessoa da linha é o técnico (o vendedor vem
# junto, com filtro próprio, como o tipo de atendimento). "Em aberto" = fora das situações travadas das Configurações
# (FECHADA/CANCELADA/PERDIDA); "Atrasada" = aberta com a previsão vencida.
class Outsider::Erp::Records::OrderKind < Outsider::Erp::Records::Kind
  S = Outsider::Erp::Sql

  def table = 'os'
  def person = :pessoa_codigo
  def default_view = 'open'
  def search_keys = %i[serie]
  def date_keys = %i[data previsao entrega]
  def seller = :vendedor_codigo
  def dimensions = { atendimento: { column: :atendimento }, vendedor: { column: :vendedor_codigo, name: :vendedor, numeric: true } }
  def extra_sorts = { 'previsao' => 'X.previsao', 'atendimento' => 'X.atendimento', 'vendedor' => 'X.vendedor' }

  def columns
    {
      numero: %w[CodigoOS], data: %w[DataEntrada], status: %w[Situacao], total: %w[Total], cliente_codigo: %w[CodigoCliente],
      pessoa_codigo: %w[Tecnico], previsao: %w[DataPrevisao], entrega: %w[DataEntrega], serie: %w[NSerie],
      equipamento: %w[Modelo DescricaoMaquina Equipamento DescrEquipto], substatus: %w[SubStatus], orcamento: %w[Orcamento],
      pedido: %w[Pedido], atendimento: %w[TipoAtendimento], vendedor_codigo: %w[Vendedor]
    }
  end

  def views
    closed = locked
    [
      { key: 'open', status_not_in: closed }, { key: 'late', late: true }, { key: 'closed', status_in: ['FECHADA'] },
      { key: 'canceled', status_in: closed - ['FECHADA'] }, { key: 'all' }
    ]
  end

  def late_sql
    "(X.previsao IS NOT NULL AND X.previsao < CURDATE() AND #{open_sql})"
  end

  private

  def locked
    list = @settings.locked_statuses
    list.empty? ? %w[FECHADA CANCELADA PERDIDA] : list
  end

  def open_sql
    "(X.status IS NULL OR X.status NOT IN (#{locked.map { |item| S.str(item) }.join(', ')}))"
  end
end
