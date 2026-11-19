# OUTSIDER: vendedores da unidade (cadastro de funcionários do ERP) para o seletor do orçamento: o código que vai no
# Vendedor do orçamento e sai com o nome embaixo da assinatura do PDF. Só leitura, filtrado pelo banco; fica no Redis por
# uma hora. Sem as colunas esperadas, a lista vem vazia (a tela avisa).
class Outsider::Erp::Sellers
  S = Outsider::Erp::Sql
  TABLE = 'funcionarios'.freeze
  ACTIVE = %w[Ativo].freeze
  SELLER = %w[Vendedor].freeze
  TTL = 1.hour
  MAX = 500

  def initialize(account, client: nil)
    @account = account
    @client = client || Outsider::Erp::Client.new(Outsider::Erp::Settings.new(account))
    @schema = Outsider::Erp::Schema.new(account, client: @client)
  end

  # [{ codigo:, nome: }] em ordem alfabética
  def list(company)
    key = "outsider_erp:#{@account.id}:sellers:#{company}"
    raw = Redis::Alfred.get(key)
    return JSON.parse(raw, symbolize_names: true) if raw

    rows = read(company)
    Redis::Alfred.set(key, rows.to_json, ex: TTL.to_i) if rows.any?
    rows
  end

  private

  def read(company)
    code = @schema.pick(company, TABLE, Outsider::Erp::SellerName::CODE)
    name = @schema.pick(company, TABLE, Outsider::Erp::SellerName::NAME)
    return [] unless code && name

    rows = @client.query_execute(sql(company, code, name)).grep(Hash).select { |row| row['codigo'].to_i.positive? && row['nome'].present? }
    only_sellers(rows).map { |row| { codigo: row['codigo'].to_i, nome: row['nome'].to_s.squish } }
  end

  # quem está marcado como vendedor no cadastro; sem ninguém marcado, todos
  def only_sellers(rows)
    rows.select { |row| row['vendedor'].to_i == 1 }.presence || rows
  end

  def sql(company, code, name)
    active = @schema.pick(company, TABLE, ACTIVE)
    where = active ? "WHERE (F.#{S.column(active)} IS NULL OR F.#{S.column(active)} <> 0)" : ''
    seller = @schema.pick(company, TABLE, SELLER)
    "SELECT F.#{S.column(code)} AS codigo, F.#{S.column(name)} AS nome, #{seller ? "F.#{S.column(seller)}" : 'NULL'} AS vendedor " \
      "FROM #{S.ident(company)}.#{TABLE} F #{where} " \
      "ORDER BY F.#{S.column(name)} LIMIT #{MAX}"
  end
end
