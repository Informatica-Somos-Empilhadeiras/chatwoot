# OUTSIDER: busca de produtos do ERP (tabela Produtos de uma unidade), para vincular a um item da proposta — assim o
# item carrega o CodigoProduto real e os impostos do orçamento saem certos. Só leitura, via query_execute, sempre
# escopada numa unidade da Somos (o banco é validado contra a lista das Configurações).
class Outsider::Erp::Catalog
  S = Outsider::Erp::Sql
  LIMIT = 30
  MIN = 2

  def initialize(account)
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  # company: banco da unidade (precisa estar nas Configurações); query: número do produto ou parte da descrição
  def search(company, query)
    company = scoped_company(company)
    query = query.to_s.strip
    return [] if query.length < MIN

    @client.query_execute(sql(company, query)).grep(Hash).map do |row|
      { codigo: row['CodigoProduto'], descricao: row['Descricao'] }
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

  def sql(company, query)
    where = query.match?(/\A\d+\z/) ? "P.CodigoProduto = #{S.int(query)}" : "P.Descricao LIKE #{S.str("%#{query}%")}"
    "SELECT P.CodigoProduto, P.Descricao FROM #{S.ident(company)}.produtos P " \
      "WHERE #{where} ORDER BY P.Descricao LIMIT #{LIMIT}"
  end
end
