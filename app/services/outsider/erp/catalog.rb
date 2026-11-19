# OUTSIDER: lista de produtos do ERP (tabela produtos de uma unidade), para vincular a um item da proposta — assim o
# item carrega o CodigoProduto real e os impostos do orçamento saem certos. Só leitura, via query_execute, sempre
# escopada numa unidade da Somos (o banco é validado contra a lista das Configurações). A lista já abre com os primeiros
# em ordem alfabética; o filtro é por número ou por palavras da descrição (a coluna vem do Outsider::Erp::Schema).
class Outsider::Erp::Catalog
  S = Outsider::Erp::Sql
  LIMIT = 50
  MAX_WORDS = 5
  DESCRIPTION = %w[Descricao DescricaoProduto Nome].freeze

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  # company: banco da unidade (precisa estar nas Configurações); query: vazio, número do produto ou palavras da descrição
  def search(company, query)
    company = scoped_company(company)
    column = description_column(company)
    @client.query_execute(sql(company, column, query.to_s.squish)).grep(Hash).map do |row|
      { codigo: row['codigo'], descricao: row['descricao'].to_s.squish }
    end
  end

  # dos CodigoProduto pedidos, quais existem mesmo na unidade (para o orçamento não perder item em silêncio:
  # a função do ERP ignora código inexistente sem erro). Devolve a lista de códigos presentes.
  def existing_codes(company, codes)
    company = scoped_company(company)
    codes = Array(codes).filter_map { |code| Integer(code, exception: false) }.uniq
    return [] if codes.empty?

    in_list = codes.map { |code| S.int(code) }.join(', ')
    sql = "SELECT P.CodigoProduto FROM #{S.ident(company)}.produtos P WHERE P.CodigoProduto IN (#{in_list})"
    @client.query_execute(sql).grep(Hash).map { |row| row['CodigoProduto'].to_i }
  end

  private

  def scoped_company(company)
    company = company.to_s
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company)

    company
  end

  def description_column(company)
    column = Outsider::Erp::Schema.new(@account, client: @client).pick(company, 'produtos', DESCRIPTION)
    raise Outsider::Erp::Client::Error, 'produtos sem coluna de descrição' unless column

    "P.#{S.column(column)}"
  end

  def sql(company, column, query)
    "SELECT P.CodigoProduto AS codigo, #{column} AS descricao FROM #{S.ident(company)}.produtos P" \
      "#{filter(column, query)} ORDER BY #{column} LIMIT #{LIMIT}"
  end

  # número: o código ou a descrição com ele; texto: todas as palavras na descrição
  def filter(column, query)
    return '' if query.empty?
    return " WHERE (P.CodigoProduto = #{S.int(query)} OR #{column} LIKE #{S.str("%#{query}%")})" if query.match?(/\A\d{1,9}\z/)

    " WHERE #{query.split.first(MAX_WORDS).map { |word| "#{column} LIKE #{S.str("%#{word}%")}" }.join(' AND ')}"
  end
end
