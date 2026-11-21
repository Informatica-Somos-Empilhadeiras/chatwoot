# OUTSIDER: lista de produtos e serviços do ERP (tabela produtos de uma unidade) para montar o orçamento de peças e
# serviços: já abre com os primeiros em ordem alfabética e filtra por número, código de fábrica ou palavras da descrição.
# Traz preço de venda, unidade, tipo (0 peça, 1 serviço), NCM e estoque, para o agente acertar quantidade e valor na
# hora de escolher. Só leitura, via query_execute, sempre escopada numa unidade da Somos (o banco é validado contra a
# lista das Configurações); as colunas vêm do information_schema (Outsider::Erp::Schema), as que existirem.
class Outsider::Erp::Catalog
  S = Outsider::Erp::Sql
  TABLE = 'produtos'.freeze
  LIMIT = 50
  MAX_WORDS = 5
  DESCRIPTION = %w[Descricao DescricaoProduto Nome].freeze
  # chave na resposta => colunas candidatas (vale a primeira que existir na unidade)
  FIELDS = {
    'preco' => %w[PrecoVenda], 'unidade' => %w[Unidade], 'tipo' => %w[Tipo], 'ncm' => %w[ClasFiscal],
    'estoque' => %w[estoqueDisponivel estoque], 'fabrica' => %w[CodigoFabrica], 'bloqueado' => %w[ckBloqueadoVenda]
  }.freeze
  ACTIVE = %w[Ativo].freeze
  TECHNICAL = %w[DescrTec].freeze

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  # company: banco da unidade (precisa estar nas Configurações); query: vazio, número/código de fábrica ou palavras
  def search(company, query)
    company = scoped_company(company)
    column = description_column(company)
    @client.query_execute(sql(company, column, query.to_s.squish)).grep(Hash).map { |row| present(row) }
  end

  # descrição técnica de um produto (aberta só quando o agente pede, para a lista não pesar)
  def technical(company, code)
    company = scoped_company(company)
    column = schema.pick(company, TABLE, TECHNICAL)
    return '' unless column

    sql = "SELECT P.#{S.column(column)} AS tecnica FROM #{S.ident(company)}.produtos P WHERE P.CodigoProduto = #{S.int(code)}"
    @client.query_execute(sql).grep(Hash).first.to_h['tecnica'].to_s.strip
  end

  # dos CodigoProduto pedidos, os que existem na unidade, com o tipo de cada um (0 peça, 1 serviço). O ERP ignora em
  # silêncio código inexistente, então o orçamento confere antes; e o tipo decide como o item é gravado.
  def kinds(company, codes)
    company = scoped_company(company)
    codes = Array(codes).filter_map { |code| Integer(code, exception: false) }.uniq
    return {} if codes.empty?

    tipo = schema.pick(company, TABLE, %w[Tipo])
    sql = "SELECT P.CodigoProduto AS codigo, #{tipo ? "P.#{S.column(tipo)}" : '0'} AS tipo FROM #{S.ident(company)}.produtos P " \
          "WHERE P.CodigoProduto IN (#{codes.map { |code| S.int(code) }.join(', ')})"
    @client.query_execute(sql).grep(Hash).to_h { |row| [row['codigo'].to_i, row['tipo'].to_i] }
  end

  def existing_codes(company, codes) = kinds(company, codes).keys

  # um produto na forma da lista, mesmo inativo (o cabeçalho do detalhe na aba Produtos); nil se não existe
  def product(company, code)
    company = scoped_company(company)
    column = description_column(company)
    sql = "SELECT P.CodigoProduto AS codigo, #{column} AS descricao, #{schema.select_list(company, TABLE, 'P', FIELDS)} " \
          "FROM #{S.ident(company)}.produtos P WHERE P.CodigoProduto = #{S.int(code)}"
    row = @client.query_execute(sql).grep(Hash).first
    row && present(row)
  end

  private

  def schema
    @schema ||= Outsider::Erp::Schema.new(@account, client: @client)
  end

  def scoped_company(company)
    company = company.to_s
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company)

    company
  end

  def description_column(company)
    column = schema.pick(company, TABLE, DESCRIPTION)
    raise Outsider::Erp::Client::Error, 'produtos sem coluna de descrição' unless column

    "P.#{S.column(column)}"
  end

  def sql(company, column, query)
    fields = schema.select_list(company, TABLE, 'P', FIELDS)
    "SELECT P.CodigoProduto AS codigo, #{column} AS descricao, #{fields} FROM #{S.ident(company)}.produtos P " \
      "WHERE #{conditions(company, column, query).join(' AND ')} ORDER BY #{exact_first(query)}#{column} LIMIT #{LIMIT}"
  end

  # buscando um número, o produto com esse código vem primeiro (antes dos que só têm o número no nome)
  def exact_first(query) = query.match?(/\A\d{1,9}\z/) ? "P.CodigoProduto = #{S.int(query)} DESC, " : ''

  # só os ativos; número: o código, o código de fábrica ou a descrição com ele; texto: todas as palavras na descrição
  def conditions(company, column, query)
    active = schema.pick(company, TABLE, ACTIVE)
    list = [active ? "(P.#{S.column(active)} IS NULL OR P.#{S.column(active)} <> 0)" : '1 = 1']
    return list if query.empty?

    list + [query_condition(company, column, query)]
  end

  def query_condition(company, column, query)
    fabrica = schema.pick(company, TABLE, FIELDS['fabrica'])
    by_factory = fabrica ? " OR P.#{S.column(fabrica)} LIKE #{S.str("%#{query}%")}" : ''
    return "(P.CodigoProduto = #{S.int(query)} OR #{column} LIKE #{S.str("%#{query}%")}#{by_factory})" if query.match?(/\A\d{1,9}\z/)

    "((#{query.split.first(MAX_WORDS).map { |word| "#{column} LIKE #{S.str("%#{word}%")}" }.join(' AND ')})#{by_factory})"
  end

  def present(row)
    text = %w[unidade ncm fabrica].to_h { |key| [key.to_sym, row[key].to_s.strip.presence] }
    {
      codigo: row['codigo'].to_i, descricao: row['descricao'].to_s.squish, tipo: row['tipo'].to_i == 1 ? 1 : 0,
      preco: row['preco'].to_f.round(2), estoque: row['estoque']&.to_f, bloqueado: row['bloqueado'].to_i == 1
    }.merge(text)
  end
end
