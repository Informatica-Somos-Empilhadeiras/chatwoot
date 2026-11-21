# OUTSIDER: a corrente de um registro do ERP: o orçamento de origem, as OS, os pedidos e as notas fiscais (de produtos,
# NF-e, e de serviços, NFS-e). Os vínculos que o Mais Prático preenche de verdade (descoberta de 20/11/2026):
# os.Orcamento e pedido.orcamento -> orçamento, orcamento.OrdemServico -> OS, pedido.OS -> OS, notafiscal.Pedido e
# notafiscalservico.Pedido -> pedido. Os.Pedido, os.NotaFiscal e pedido.NotaFiscal ficam sempre vazios e não são usados.
# Aqui tudo vira uma lista só, para o painel mostrar os nós clicáveis e a linha do tempo. Só leitura, no banco da unidade.
class Outsider::Erp::Records::Chain
  S = Outsider::Erp::Sql
  LIMIT = 20
  QUOTE = { 'numero' => %w[codigoorcamento], 'data' => %w[orcamentoData], 'status' => %w[Status], 'total' => %w[total],
            'os' => %w[OrdemServico] }.freeze
  ORDER = { 'numero' => %w[CodigoOS], 'data' => %w[DataEntrada], 'status' => %w[Situacao], 'total' => %w[Total], 'entrega' => %w[DataEntrega],
            'orcamento' => %w[Orcamento] }.freeze
  SALE = { 'numero' => %w[CodigoPedido], 'data' => %w[PedidoData], 'status' => %w[Status Situacao], 'total' => %w[total Total],
           'orcamento' => %w[orcamento Orcamento], 'os' => %w[OS], 'fechado' => %w[fechado] }.freeze
  INVOICE = { 'numero' => %w[CodigoNF], 'data' => %w[Emissao], 'status' => %w[Status], 'total' => %w[TotalNF total],
              'pedido' => %w[Pedido], 'tipo' => %w[TipoNota] }.freeze
  SERVICE_INVOICE = { 'numero' => %w[SeqNFSe], 'data' => %w[Emissao], 'status' => %w[Status], 'total' => %w[TotalNF Total],
                      'pedido' => %w[Pedido], 'nfse' => %w[CodigoNFS], 'rps' => %w[CodigoRps] }.freeze

  def initialize(account, company, schema:, client:)
    @account = account
    @company = company
    @schema = schema
    @client = client
  end

  KINDS = %w[quotes orders sales invoices service_invoices].freeze

  # nós em ordem: orçamento, OS, pedidos, NF-e, NFS-e; o registro aberto vem com current: true
  def build(kind, number, header)
    rows = collect(seeds(kind, number, header))
    list = KINDS.flat_map { |name| rows[name].map { |row| node(name, row) } }
    list.uniq { |row| [row['kind'], row['numero']] }.map { |row| row.merge('current' => row['kind'] == kind && row['numero'] == number) }
  end

  private

  # o ponto de partida: o que o próprio registro aberto já diz da corrente
  def seeds(kind, number, header)
    seeds = { quote: header['orcamento'].to_i, orders: ids(header['os']), sales: ids(header['pedido']), invoices: [], services: [] }
    case kind
    when 'quotes' then seeds.merge(quote: number)
    when 'orders' then seeds.merge(orders: [number])
    when 'sales' then seeds.merge(sales: [number])
    when 'invoices' then seeds.merge(invoices: [number])
    when 'service_invoices' then seeds.merge(services: [number])
    else seeds
    end
  end

  # a corrente inteira e as notas dos pedidos
  def collect(seeds)
    quote, orders, sales = linked(seeds)
    { 'quotes' => [quote].compact, 'orders' => orders, 'sales' => sales,
      'invoices' => notes('notafiscal', INVOICE, sales, seeds[:invoices]),
      'service_invoices' => notes('notafiscalservico', SERVICE_INVOICE, sales, seeds[:services]) }
  end

  # orçamento, OS e pedidos ligados entre si
  def linked(seeds)
    sales = sales_by_ids(seeds[:sales])
    quote_number = seeds[:quote].nonzero? || first_positive(sales.pluck('orcamento'))
    quote = quote(quote_number)
    orders = orders(quote_number, seeds[:orders] + ids(quote&.dig('os')) + ids(*sales.pluck('os')))
    sales = union_rows(sales, sales(quote_number, orders.pluck('numero')))
    # OS sem orçamento, mas com pedido que veio de um orçamento
    [quote || quote(first_positive(sales.pluck('orcamento') + orders.pluck('orcamento'))), orders, sales]
  end

  def quote(number)
    fetch('orcamento', QUOTE, "numero_col = #{S.int(number)}").first if number.positive?
  end

  # números válidos (false/nil ficam de fora)
  def ids(*values) = values.map { |value| value.respond_to?(:to_i) ? value.to_i : 0 }.select(&:positive?).uniq
  def first_positive(values) = ids(*values).first || 0
  def in_list(values) = ids(*values).join(', ')
  def union_rows(*lists) = lists.flatten.uniq { |row| row['numero'].to_i }

  def orders(quote_number, ids)
    conditions = []
    conditions << "orcamento_col = #{S.int(quote_number)}" if quote_number.positive?
    conditions << "numero_col IN (#{in_list(ids)})" if ids.any?
    conditions.empty? ? [] : fetch('os', ORDER, conditions.join(' OR '))
  end

  def sales_by_ids(ids) = ids.any? ? fetch('pedido', SALE, "numero_col IN (#{in_list(ids)})") : []

  # pedidos do orçamento e os que apontam para as OS da corrente (pedido.OS)
  def sales(quote_number, order_ids)
    conditions = []
    conditions << "orcamento_col = #{S.int(quote_number)}" if quote_number.positive?
    conditions << "os_col IN (#{in_list(order_ids)})" if ids(*order_ids).any?
    conditions.empty? ? [] : fetch('pedido', SALE, conditions.join(' OR '))
  end

  # notas dos pedidos da corrente (e a própria nota aberta)
  def notes(table, mapping, sales, ids)
    conditions = []
    sale_ids = ids(*sales.pluck('numero'))
    conditions << "pedido_col IN (#{in_list(sale_ids)})" if sale_ids.any?
    conditions << "numero_col IN (#{in_list(ids)})" if ids.any?
    conditions.empty? ? [] : fetch(table, mapping, conditions.join(' OR '))
  end

  # SELECT com as colunas que existem; "<chave>_col" na condição vira a coluna real (ou NULL, se não existir)
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

  # a situação do pedido no ERP (FINALIZADO, ABERTO, CANCELADO...); sem ela, o "fechado" do pedido
  def sale_status(row)
    status = row['status'].to_s.strip
    return status if status.present?

    row['fechado'].to_i.zero? ? 'ABERTO' : 'FECHADO'
  end

  # NFS-e: o número da prefeitura; antes dele, o RPS; pausada/sem envio, nada (a tela mostra a situação)
  def service_label(row)
    return row['nfse'].to_i.to_s if row['nfse'].to_i.positive?

    "RPS #{row['rps'].to_i}" if row['rps'].to_i.positive?
  end

  def node(kind, row)
    {
      'kind' => kind, 'company' => @company, 'numero' => row['numero'].to_i, 'data' => row['data'], 'status' => row['status'].to_s.strip.presence,
      'total' => row['total'].to_f.round(2), 'entrega' => row['entrega']
    }.compact.merge(extras(kind, row))
  end

  def extras(kind, row)
    case kind
    when 'sales' then { 'status' => sale_status(row) }
    when 'invoices' then { 'pedido' => row['pedido'].to_i.nonzero?, 'entrada' => row['tipo'].to_i == 1 }
    when 'service_invoices' then { 'rotulo' => service_label(row), 'pedido' => row['pedido'].to_i.nonzero? }
    else {}
    end.compact
  end
end
