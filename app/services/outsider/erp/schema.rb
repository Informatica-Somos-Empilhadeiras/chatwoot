# OUTSIDER: quais colunas uma tabela do ERP tem no banco de uma unidade (information_schema, só leitura, sempre
# filtrado pelo banco da unidade). Assim as listas (clientes, produtos) escolhem as colunas que existem em vez de supor
# o nome; se o ERP mudar de versão, a lista se ajusta. Fica em cache no Redis por um dia.
class Outsider::Erp::Schema
  S = Outsider::Erp::Sql
  TABLES = %w[clientes produtos formapagto orcamento detalheorcamento empresa funcionarios ac_desconto os detalheos pedido
              detalhepedido notafiscal detalhenf notafiscalservico detalhenfservico contrato detalhecontrato faturacontrato
              detalhefaturacontrato faturacontratocorrelacao equipamentos].freeze
  TTL = 1.day

  def initialize(account, client: nil)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = client || Outsider::Erp::Client.new(@settings)
    @memo = {}
  end

  # nomes das colunas como o MySQL devolve (ex.: "CodigoCliente")
  def columns(company, table)
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company)
    raise ArgumentError, 'tabela' unless TABLES.include?(table)

    @memo[[company, table]] ||= cached("outsider_erp:#{@account.id}:schema:#{company}:#{table}") { read(company, table) }
  end

  # a primeira das candidatas que existe na tabela (sem diferenciar maiúsculas), ou nil
  def pick(company, table, candidates)
    existing = columns(company, table).index_by(&:downcase)
    candidates.lazy.filter_map { |name| existing[name.downcase] }.first
  end

  # lista do SELECT com as colunas que existem: { 'chave' => %w[Candidatas] } vira "A.`Coluna` AS chave" ou "NULL AS chave"
  # quando nenhuma candidata existe nessa unidade (o relatório sai com o campo vazio em vez de quebrar)
  def select_list(company, table, table_alias, mapping)
    mapping.map do |key, candidates|
      column = pick(company, table, Array(candidates))
      column ? "#{table_alias}.#{S.column(column)} AS #{key}" : "NULL AS #{key}"
    end.join(', ')
  end

  private

  def read(company, table)
    sql = "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = #{S.str(company)} " \
          "AND LOWER(TABLE_NAME) = #{S.str(table)} ORDER BY ORDINAL_POSITION"
    @client.query_execute(sql).grep(Hash).filter_map { |row| row['COLUMN_NAME'] || row['column_name'] }.grep(S::COLUMN)
  end

  def cached(key)
    raw = Redis::Alfred.get(key)
    return JSON.parse(raw) if raw

    list = yield
    Redis::Alfred.set(key, list.to_json, ex: TTL.to_i) if list.any?
    list
  end
end
