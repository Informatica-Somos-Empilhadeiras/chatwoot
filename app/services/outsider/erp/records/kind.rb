# OUTSIDER: o que cada lista da seção ERP lê do banco do ERP (orçamentos, OS, pedidos, NF-e, NFS-e): tabela, colunas (candidatas,
# conferidas no information_schema por Outsider::Erp::Schema), quem é a pessoa da linha (vendedor ou técnico) e as
# visões rápidas (abas "Em negociação", "Atrasadas"...). Só descreve; quem monta o SQL é Outsider::Erp::Records::Query.
# Locação e máquinas: contratos (contrato), máquinas (equipamentos) e faturas de locação (faturacontrato).
class Outsider::Erp::Records::Kind
  KINDS = %w[quotes orders sales invoices service_invoices contracts machines rental_invoices].freeze

  CLASSES = {
    'quotes' => 'QuoteKind', 'orders' => 'OrderKind', 'sales' => 'SaleKind', 'invoices' => 'InvoiceKind',
    'service_invoices' => 'ServiceInvoiceKind', 'contracts' => 'ContractKind', 'machines' => 'MachineKind',
    'rental_invoices' => 'RentalInvoiceKind'
  }.freeze

  def self.for(name, settings, client: nil)
    "Outsider::Erp::Records::#{CLASSES.fetch(name.to_s) { raise ArgumentError, 'tipo' }}".constantize.new(settings, client)
  end

  def initialize(settings, client = nil)
    @settings = settings
    @client = client
  end

  # chave => colunas candidatas na tabela principal (a primeira que existir)
  def columns = raise(NotImplementedError)
  def table = raise(NotImplementedError)
  # chave da coluna com o código da pessoa da linha (funcionarios)
  def person = raise(NotImplementedError)
  def views = [{ key: 'all' }]
  def default_view = 'all'
  # colunas que a busca por texto também olha, além do cliente
  def search_keys = []
  # colunas numéricas que a busca por número olha (a NFS-e procura também o número da prefeitura)
  def number_keys = %i[numero]
  # colunas de texto que a busca só com algarismos também olha (série e patrimônio da máquina)
  def digit_keys = []
  # visões montadas das próprias situações que aparecem nas contagens (pedidos e notas)
  def status_views? = false
  def required = %i[numero data cliente_codigo]
  # chaves com data (viram AAAA-MM-DD na resposta)
  def date_keys = %i[data]
  # expressão SQL da situação; nil = não tem
  def status_sql(picked) = picked[:status] && "O.#{Outsider::Erp::Sql.column(picked[:status])}"
  # colunas calculadas de outras tabelas do mesmo banco (["(SELECT ...) AS chave"]), depois das colunas da tabela
  def computed(_company, _schema) = []
  # LEFT JOINs extras da unidade (antes do cliente e da pessoa), para as colunas calculadas e a situação montada
  def joins(_company, _schema) = ''
  # unidades que entram na lista (as máquinas só das que têm cadastro próprio, sem repetir)
  def companies(list) = list
  # expressão do código do cliente da linha (a máquina locada mostra o cliente do contrato)
  def client_sql(picked) = "O.#{Outsider::Erp::Sql.column(picked[:cliente_codigo])}"
  # expressão SQL de "atrasada" sobre a linha já montada (X.*); só as OS têm
  def late_sql = '0'
  # chave (em columns) do código do vendedor quando a pessoa da linha é outra (na OS, o técnico); a linha ganha "vendedor"
  def seller = nil
  # filtros extras com contagem: filtro => { column: chave em columns, name: chave do nome (opcional), numeric: código }
  def dimensions = {}
  # ordenações além das comuns (data, número, total, cliente, pessoa)
  def extra_sorts = {}

  def view(key)
    key = key.to_s
    return { key: key, status_in: [key.delete_prefix('status:').first(40)] } if key.start_with?('status:')

    views.find { |item| item[:key] == key } || views.find { |item| item[:key] == default_view }
  end
end
