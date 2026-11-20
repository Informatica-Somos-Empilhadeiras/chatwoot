# OUTSIDER: os pedidos de venda do ERP (PedidoVenda/valoresDash), espelho como os orcamentos e so para visualizacao.
# A API devolve o CNPJ no lugar do banco, entao cada empresa e buscada separada e ganha o campo Banco. A listagem
# pagina e busca na nossa camada (o ERP devolve tudo de uma vez; aqui recortamos para nao jogar milhares na tela).
class Outsider::Erp::SalesOrders
  FIELDS = %w[Codigo CodigoCliente Cliente Cidade UF Emissao DataStatus Status Substatus ValorTotal Vendedor Tipo Doc Segmento].freeze
  PER_DEFAULT = 30
  PER_MAX = 100

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
  end

  def snapshot
    @snapshot ||= Outsider::Erp::Snapshot.new(@account, 'sales_orders', ttl: @settings.data['quotes_cache_seconds'], loader: method(:load), sync: false)
  end

  def fetch = @fetch ||= snapshot.fetch
  def meta = { fetched_at: Time.zone.at(fetch['at']).iso8601, stale: fetch['stale'] }

  # pagina (mais novos primeiro) com busca por numero do pedido ou nome do cliente
  def page(page: nil, per: nil, query: nil)
    per = per.to_i
    per = PER_DEFAULT if per < 1
    per = PER_MAX if per > PER_MAX
    page = [page.to_i, 1].max
    rows = sorted
    rows = filter(rows, query) if query.to_s.strip.present?
    { page: page, per: per, total: rows.size, items: rows.slice((page - 1) * per, per) || [] }
  end

  private

  def sorted
    fetch['items'].sort_by { |item| item['Emissao'].to_s }.reverse
  end

  def filter(rows, query)
    words = Outsider::Erp::ServiceOrders.words(query)
    rows.select { |item| Outsider::Erp::ServiceOrders.matches?(words, "#{item['Codigo']} #{item['Cliente']}") }
  end

  def load(read_timeout)
    client = Outsider::Erp::Client.new(@settings)
    @settings.companies.flat_map do |company|
      client.sales_orders(company, read_timeout: read_timeout).map { |item| item.slice(*FIELDS).merge('Banco' => company) }
    end
  end
end
