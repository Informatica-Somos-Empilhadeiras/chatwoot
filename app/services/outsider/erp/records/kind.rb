# OUTSIDER: o que cada lista da seção ERP lê do banco do ERP (orçamentos, OS, pedidos): tabela, colunas (candidatas,
# conferidas no information_schema por Outsider::Erp::Schema), quem é a pessoa da linha (vendedor ou técnico) e as
# visões rápidas (abas "Em negociação", "Atrasadas"...). Só descreve; quem monta o SQL é Outsider::Erp::Records::Query.
class Outsider::Erp::Records::Kind
  KINDS = %w[quotes orders sales].freeze

  def self.for(name, settings)
    case name.to_s
    when 'quotes' then Outsider::Erp::Records::QuoteKind.new(settings)
    when 'orders' then Outsider::Erp::Records::OrderKind.new(settings)
    when 'sales' then Outsider::Erp::Records::SaleKind.new(settings)
    else raise ArgumentError, 'tipo'
    end
  end

  def initialize(settings)
    @settings = settings
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
  def required = %i[numero data cliente_codigo]
  # chaves com data (viram AAAA-MM-DD na resposta)
  def date_keys = %i[data]
  # expressão SQL da situação; nil = não tem
  def status_sql(picked) = picked[:status] && "O.#{Outsider::Erp::Sql.column(picked[:status])}"
  # expressão SQL de "atrasada" sobre a linha já montada (X.*); só as OS têm
  def late_sql = '0'

  def view(key)
    key = key.to_s
    return { key: key, status_in: [key.delete_prefix('status:').first(40)] } if key.start_with?('status:')

    views.find { |item| item[:key] == key } || views.find { |item| item[:key] == default_view }
  end
end
