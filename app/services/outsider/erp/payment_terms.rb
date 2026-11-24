# OUTSIDER: formas de pagamento do ERP (tabela formapagto das unidades), para escolher a do orçamento numa lista com o
# nome em vez do código. Só leitura, via query_execute, banco a banco. O mesmo código com descrições diferentes entre as
# unidades aparece junto ("BOLETO / À VISTA"), para ninguém escolher às cegas. As colunas saem do Outsider::Erp::Schema
# (o nome pode mudar entre versões do ERP); uma unidade que falha não derruba a lista das outras. Cache de 1 hora.
class Outsider::Erp::PaymentTerms
  S = Outsider::Erp::Sql
  READ_TIMEOUT = 8
  MAX = 500
  TTL = 1.hour
  CODE_COLUMNS = %w[Codigo CodigoFormaPagto CodFormaPagto CodigoForma].freeze
  NAME_COLUMNS = %w[Descricao DescricaoFormaPagto Nome FormaPagto].freeze

  attr_reader :errors

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(account, client: @client)
    @errors = []
  end

  # [{ codigo:, descricao: }] em ordem alfabética
  def list
    cached { read }
  end

  # nome da forma de pagamento pelo código ('' quando não acha)
  def name(code)
    list.find { |row| row[:codigo] == code.to_i }&.dig(:descricao).to_s
  end

  private

  def read
    rows = @settings.companies.flat_map { |company| company_rows(company) }
    terms = rows.group_by { |row| row['codigo'].to_i }.except(0).map { |code, list| term(code, list) }
    terms.sort_by { |row| row[:descricao] }
  end

  def company_rows(company)
    sql = sql(company)
    return [] unless sql

    @client.query_execute(sql, read_timeout: READ_TIMEOUT).grep(Hash)
  rescue Outsider::Erp::Client::Error => e
    @errors << "#{company}: #{e.message}"
    Rails.logger.warn("[Outsider::Erp] formas de pagamento de #{company}: #{e.message}")
    []
  end

  def term(code, list)
    name = list.map { |row| row['descricao'].to_s.squish }.compact_blank.uniq.join(' / ')
    { codigo: code, descricao: name }
  end

  def sql(company)
    code = @schema.pick(company, 'formapagto', CODE_COLUMNS)
    name = @schema.pick(company, 'formapagto', NAME_COLUMNS)
    unless code && name
      @errors << "#{company}: tabela formapagto sem código ou descrição"
      return
    end

    "SELECT F.#{S.column(code)} AS codigo, F.#{S.column(name)} AS descricao FROM #{S.ident(company)}.formapagto F " \
      "ORDER BY F.#{S.column(name)} LIMIT #{MAX}"
  end

  # só guarda lista com nome (lista vazia ou sem descrição tenta de novo na próxima vez)
  def cached
    key = "outsider_erp:#{@account.id}:payment_terms:#{Digest::SHA1.hexdigest(@settings.companies.join(','))}"
    raw = Redis::Alfred.get(key)
    return JSON.parse(raw, symbolize_names: true) if raw

    terms = yield
    Redis::Alfred.set(key, terms.to_json, ex: TTL.to_i) if terms.any? { |row| row[:descricao].present? }
    terms
  end
end
