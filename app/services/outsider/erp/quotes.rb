# OUTSIDER: os orçamentos do ERP (cotacaoDesempenho, espelho como as OS). A tela de orçamentos deles pede uma empresa por
# vez e devolve o CNPJ no lugar do banco, então cada empresa é buscada separada e ganha o campo Banco. Só os campos do
# painel ficam na cópia (a resposta inteira tem dezenas de colunas de indicadores).
class Outsider::Erp::Quotes
  FIELDS = %w[CodigoOrcamento CodigoCliente Cliente Cidade UF DataCadastro Status DataStatus Vendedor OrdemServico Pedido Substatus Tipo
              TipoCliente ValorTotal ValorFechado AlertaFollow UltimoNivelFollow apelidoEmpresa].freeze
  PER_DEFAULT = 30
  PER_MAX = 100

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
  end

  def snapshot
    @snapshot ||= Outsider::Erp::Snapshot.new(@account, 'quotes', ttl: @settings.data['quotes_cache_seconds'], loader: method(:load), sync: false)
  end

  def fetch
    @fetch ||= snapshot.fetch
  end

  def meta = { fetched_at: Time.zone.at(fetch['at']).iso8601, stale: fetch['stale'] }

  # listagem global paginada (mais novos primeiro) com busca (numero/cliente) e filtros (status, empresa)
  def page(page: nil, per: nil, query: nil, status: nil, company: nil)
    per = per.to_i
    per = PER_DEFAULT if per < 1
    per = PER_MAX if per > PER_MAX
    page = [page.to_i, 1].max
    rows = fetch['items']
    rows = rows.select { |item| item['Banco'] == company } if company.present?
    rows = rows.select { |item| item['Status'].to_s.casecmp?(status.to_s) } if status.present?
    rows = filter(rows, query) if query.to_s.strip.present?
    rows = rows.sort_by { |item| item['DataCadastro'].to_s }.reverse
    { page: page, per: per, total: rows.size, items: rows.slice((page - 1) * per, per) || [] }
  end

  # opcoes para os filtros da tela (status e empresas presentes)
  def facets
    rows = fetch['items']
    { statuses: rows.filter_map { |item| item['Status'].presence }.uniq.sort,
      companies: rows.filter_map { |item| item['Banco'].presence }.uniq.sort }
  end

  # orçamentos dos clientes vinculados (empresa + código), mais novos primeiro
  def for_clients(links)
    wanted = links.to_set { |link| [link['empresa'], link['codigo'].to_i] }
    fetch['items'].select { |item| wanted.include?([item['Banco'], item['CodigoCliente'].to_i]) }
                  .sort_by { |item| item['DataCadastro'].to_s }.reverse
  end

  private

  def load(read_timeout)
    client = Outsider::Erp::Client.new(@settings)
    @settings.companies.flat_map do |company|
      client.quotes(company, read_timeout: read_timeout).map { |item| item.slice(*FIELDS).merge('Banco' => company) }
    end
  end

  def filter(rows, query)
    query = query.to_s.strip
    return rows.select { |item| item['CodigoOrcamento'].to_s == query } if query.match?(/\A\d+\z/)

    words = Outsider::Erp::ServiceOrders.words(query)
    rows.select { |item| Outsider::Erp::ServiceOrders.matches?(words, item['Cliente'].to_s) }
  end
end
