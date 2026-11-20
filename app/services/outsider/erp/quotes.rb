# OUTSIDER: os orçamentos do ERP (cotacaoDesempenho, espelho como as OS). A tela de orçamentos deles pede uma empresa por
# vez e devolve o CNPJ no lugar do banco, então cada empresa é buscada separada e ganha o campo Banco. Só os campos do
# painel ficam na cópia (a resposta inteira tem dezenas de colunas de indicadores).
class Outsider::Erp::Quotes
  FIELDS = %w[CodigoOrcamento CodigoCliente Cliente Cidade UF DataCadastro Status DataStatus Vendedor OrdemServico Pedido Substatus Tipo
              TipoCliente ValorTotal ValorFechado AlertaFollow UltimoNivelFollow apelidoEmpresa].freeze

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
end
