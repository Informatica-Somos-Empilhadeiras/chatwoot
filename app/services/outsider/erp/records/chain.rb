# OUTSIDER: a corrente de um registro do ERP: o orçamento de origem, as OS que saíram dele e os pedidos (com a nota
# fiscal). O ERP guarda os vínculos em colunas soltas (orcamento.OrdemServico, os.Orcamento, os.Pedido,
# pedido.orcamento); aqui eles viram uma lista só, para o painel mostrar os nós clicáveis e a linha do tempo. Só leitura,
# no banco da unidade.
class Outsider::Erp::Records::Chain
  S = Outsider::Erp::Sql
  LIMIT = 20
  QUOTE = { 'numero' => %w[codigoorcamento], 'data' => %w[orcamentoData], 'status' => %w[Status], 'total' => %w[total],
            'os' => %w[OrdemServico] }.freeze
  ORDER = { 'numero' => %w[CodigoOS], 'data' => %w[DataEntrada], 'status' => %w[Situacao], 'total' => %w[Total], 'entrega' => %w[DataEntrega],
            'orcamento' => %w[Orcamento], 'pedido' => %w[Pedido] }.freeze
  SALE = { 'numero' => %w[CodigoPedido], 'data' => %w[PedidoData], 'total' => %w[total Total], 'orcamento' => %w[orcamento Orcamento],
           'nota' => %w[NotaFiscal], 'fechado' => %w[fechado] }.freeze

  def initialize(account, company, schema:, client:)
    @account = account
    @company = company
    @schema = schema
    @client = client
  end

  # nós em ordem: orçamento, OS, pedidos; o registro aberto vem com current: true
  def build(kind, number, header)
    quote_number = kind == 'quotes' ? number : header['orcamento'].to_i
    quote = quote(quote_number)
    sale_ids = ids(kind == 'sales' && number, header['pedido'])
    orders = orders(quote_number, ids(kind == 'orders' && number, header['os'], quote&.dig('os')), sale_ids)
    sales = sales(quote_number, sale_ids + ids(*orders.pluck('pedido')))
    nodes(kind, number, quote, orders, sales)
  end

  private

  def quote(number)
    fetch('orcamento', QUOTE, "numero_col = #{S.int(number)}").first if number.positive?
  end

  # números válidos (false/nil ficam de fora)
  def ids(*values) = values.map { |value| value.respond_to?(:to_i) ? value.to_i : 0 }.select(&:positive?)

  def orders(quote_number, ids, sale_ids)
    conditions = []
    conditions << "orcamento_col = #{S.int(quote_number)}" if quote_number.positive?
    conditions << "numero_col IN (#{ids.uniq.join(', ')})" if ids.any?
    conditions << "pedido_col IN (#{sale_ids.uniq.join(', ')})" if sale_ids.any?
    conditions.empty? ? [] : fetch('os', ORDER, conditions.join(' OR '))
  end

  def sales(quote_number, ids)
    conditions = []
    conditions << "orcamento_col = #{S.int(quote_number)}" if quote_number.positive?
    conditions << "numero_col IN (#{ids.uniq.join(', ')})" if ids.any?
    conditions.empty? ? [] : fetch('pedido', SALE, conditions.join(' OR '))
  end

  # SELECT com as colunas que existem; "<chave>_col" na condição vira a coluna real (ou some, se não existir)
  def fetch(table, mapping, condition)
    picked = mapping.transform_values { |candidates| @schema.pick(@company, table, candidates) }
    return [] unless picked['numero']

    where = condition.gsub(/\b(\w+)_col\b/) do
      column = picked[Regexp.last_match(1)]
      column ? "O.#{S.column(column)}" : 'NULL'
    end
    sql = "SELECT #{@schema.select_list(@company, table, 'O', mapping)} FROM #{S.ident(@company)}.#{S.ident(table)} O " \
          "WHERE #{where} ORDER BY O.#{S.column(picked['numero'])} LIMIT #{LIMIT}"
    @client.query_execute(sql).grep(Hash)
  end

  def nodes(kind, number, quote, orders, sales)
    list = []
    list << node('quotes', quote) if quote
    list += orders.map { |row| node('orders', row) }
    list += sales.map { |row| node('sales', row).merge('status' => sale_status(row), 'nota' => row['nota'].to_i.nonzero?).compact }
    list.uniq { |row| [row['kind'], row['numero']] }.map { |row| row.merge('current' => row['kind'] == kind && row['numero'] == number) }
  end

  # o pedido não tem coluna de situação: faturado (tem nota), fechado ou aberto
  def sale_status(row)
    return 'FATURADO' if row['nota'].to_i.positive?

    row['fechado'].to_i.zero? ? 'ABERTO' : 'FECHADO'
  end

  def node(kind, row)
    {
      'kind' => kind, 'company' => @company, 'numero' => row['numero'].to_i, 'data' => row['data'], 'status' => row['status'].to_s.strip.presence,
      'total' => row['total'].to_f.round(2), 'entrega' => row['entrega']
    }.compact
  end
end
