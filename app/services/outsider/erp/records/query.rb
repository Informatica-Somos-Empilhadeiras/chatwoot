# OUTSIDER: o SQL das listas da seção ERP. Junta as unidades da Somos (só as das Configurações, cada uma com o nome do
# banco na frente) num UNION e filtra/pagina por cima, direto no banco do ERP: assim a lista tem TODO o histórico, sem
# janela de datas. Só SELECT; todo valor vindo da tela passa por Outsider::Erp::Sql. Cada linha ganha cliente (clientes) e
# a pessoa (funcionarios: vendedor ou técnico).
class Outsider::Erp::Records::Query
  S = Outsider::Erp::Sql
  CLIENT = {
    cliente: %w[Nome RazaoSocial], fantasia: %w[Apelido Fantasia NomeFantasia], cidade: %w[Cidade], uf: %w[UF Estado],
    cnpj: %w[CPF_CNPJ CNPJ CPF]
  }.freeze
  SORTS = { 'data' => 'X.data', 'numero' => 'X.numero', 'total' => 'X.total', 'cliente' => 'X.cliente', 'pessoa' => 'X.pessoa' }.freeze
  # ordenações por texto (e a previsão da OS): linha sem o valor vai para o fim, nos dois sentidos
  TEXT_SORTS = %w[cliente pessoa atendimento vendedor].freeze
  DATE_SORTS = %w[previsao].freeze
  TEXT_KEYS = %i[cliente fantasia cidade].freeze

  def initialize(kind, schema)
    @kind = kind
    @schema = schema
  end

  # linhas da página (filtros: q, from, to, clients, dimensions, view, person, mine)
  # options: sort, direction, per, offset
  def page_sql(companies, filters, options)
    union = union(companies)
    return unless union

    direction = options[:direction].to_s == 'asc' ? 'ASC' : 'DESC'
    "SELECT X.* FROM (#{union}) X WHERE #{where(filters, full: true)} " \
      "ORDER BY #{order(options[:sort].to_s, direction)}, X.numero #{direction}, X.banco " \
      "LIMIT #{Integer(options[:per])} OFFSET #{Integer(options[:offset])}"
  end

  # contagem de cada valor dos filtros extras do tipo (na OS: tipo de atendimento e vendedor). Cada filtro conta com os
  # outros aplicados, menos ele mesmo, para a lista dele não encolher para um item só.
  def dimensions_sql(companies, filters)
    union = union(companies)
    return unless union && @kind.dimensions.any?

    @kind.dimensions.map do |key, definition|
      value = dimension_value(definition)
      name = definition[:name] ? "MAX(X.#{definition[:name]})" : 'NULL'
      others = filters.merge(dimensions: filters[:dimensions].to_h.except(key))
      "SELECT #{S.str(key.to_s)} AS dim, #{value} AS valor, #{name} AS nome, COUNT(*) AS qtd FROM (#{union}) X " \
        "WHERE #{where(others, full: true)} AND #{value} IS NOT NULL GROUP BY #{value}"
    end.join(' UNION ALL ')
  end

  # contagens por unidade x situação x pessoa x atrasada, com os filtros de base (busca, período, cliente); as visões,
  # a unidade e a pessoa são aplicadas por cima em Ruby (Outsider::Erp::Records::Facets)
  def facets_sql(companies, filters)
    union = union(companies)
    return unless union

    "SELECT X.banco, X.status, X.pessoa_codigo, X.pessoa, #{@kind.late_sql} AS atrasada, COUNT(*) AS qtd, " \
      "SUM(IFNULL(X.total, 0)) AS soma FROM (#{union}) X WHERE #{where(filters, full: false)} " \
      'GROUP BY X.banco, X.status, X.pessoa_codigo, X.pessoa, atrasada'
  end

  private

  def order(key, direction)
    column = SORTS.merge(@kind.extra_sorts).fetch(key, 'X.data')
    return "(#{column} IS NULL OR #{column} = '') ASC, #{column} #{direction}" if TEXT_SORTS.include?(key)
    return "(#{column} IS NULL) ASC, #{column} #{direction}" if DATE_SORTS.include?(key)

    "#{column} #{direction}"
  end

  def union(companies)
    selects = companies.filter_map { |company| bank_select(company) }
    selects.empty? ? nil : selects.join(' UNION ALL ')
  end

  # SELECT de uma unidade com as colunas que existem nela; nil quando falta uma obrigatória
  def bank_select(company)
    picked = @kind.columns.transform_values { |candidates| @schema.pick(company, @kind.table, candidates) }
    return if @kind.required.any? { |key| picked[key].nil? }

    bank = S.ident(company)
    "SELECT #{S.str(company)} AS banco, #{fields(picked).join(', ')}, #{client_fields(company)}, #{person_field(company)}" \
      "#{seller_field(company, picked)} FROM #{bank}.#{S.ident(@kind.table)} O #{client_join(company, picked)} " \
      "#{person_join(company, picked)}#{seller_join(company, picked)}"
  end

  def fields(picked)
    @kind.columns.keys.map do |key|
      next "NULLIF(TRIM(#{@kind.status_sql(picked) || 'NULL'}), '') AS status" if key == :status

      picked[key] ? "O.#{S.column(picked[key])} AS #{key}" : "NULL AS #{key}"
    end
  end

  def client_fields(company)
    CLIENT.map do |key, candidates|
      column = client_code(company) && @schema.pick(company, 'clientes', candidates)
      column ? "C.#{S.column(column)} AS #{key}" : "NULL AS #{key}"
    end.join(', ')
  end

  def client_join(company, picked)
    code = client_code(company)
    return '' unless code

    "LEFT JOIN #{S.ident(company)}.clientes C ON C.#{S.column(code)} = O.#{S.column(picked[:cliente_codigo])}"
  end

  def client_code(company) = @schema.pick(company, 'clientes', %w[CodigoCliente Codigo])

  def person_field(company)
    name = person_code(company) && @schema.pick(company, 'funcionarios', Outsider::Erp::SellerName::NAME)
    name ? "P.#{S.column(name)} AS pessoa" : 'NULL AS pessoa'
  end

  def person_join(company, picked)
    code = person_code(company)
    column = picked[@kind.person]
    return '' unless code && column

    "LEFT JOIN #{S.ident(company)}.funcionarios P ON P.#{S.column(code)} = O.#{S.column(column)}"
  end

  def person_code(company) = @schema.pick(company, 'funcionarios', Outsider::Erp::SellerName::CODE)

  # nome do vendedor quando a pessoa da linha é outra (OS: técnico); toda unidade devolve a coluna, mesmo vazia
  def seller_field(company, picked)
    return '' unless @kind.seller

    name = person_code(company) && picked[@kind.seller] && @schema.pick(company, 'funcionarios', Outsider::Erp::SellerName::NAME)
    name ? ", V.#{S.column(name)} AS vendedor" : ', NULL AS vendedor'
  end

  def seller_join(company, picked)
    code = @kind.seller && person_code(company)
    column = code && picked[@kind.seller]
    return '' unless column

    " LEFT JOIN #{S.ident(company)}.funcionarios V ON V.#{S.column(code)} = O.#{S.column(column)}"
  end

  def where(filters, full:)
    parts = [search(filters[:q]), period(filters[:from], filters[:to]), clients(filters[:clients]), dimensions(filters[:dimensions])]
    parts += [view(filters[:view], filters[:mine]), person(filters[:person])] if full
    parts.compact.presence&.join(' AND ') || '1 = 1'
  end

  # só números (ou pontuação de CNPJ): número do registro ou pedaço do CPF/CNPJ; texto: cada palavra no cliente
  def search(query)
    query = query.to_s.squish.first(80)
    return if query.empty?
    return number_search(query.delete('^0-9')) if query.match?(%r{\A[\d./\-\s]+\z})

    words = query.split.first(6)
    keys = TEXT_KEYS + @kind.search_keys
    words.map { |word| "(#{keys.map { |key| "X.#{key} LIKE #{like(word)}" }.join(' OR ')})" }.join(' AND ')
  end

  def number_search(digits)
    parts = []
    number = digits.sub(/\A0+(?=\d)/, '') # zeros à esquerda (nº da chave da NF) não viram octal
    parts += @kind.number_keys.map { |key| "X.#{key} = #{S.int(number)}" } if number.size <= 15
    parts << "REPLACE(REPLACE(REPLACE(REPLACE(IFNULL(X.cnpj, ''), '.', ''), '/', ''), '-', ''), ' ', '') LIKE #{like(digits)}" if digits.size >= 4
    parts.empty? ? '1 = 0' : "(#{parts.join(' OR ')})"
  end

  def like(word) = S.str("%#{word.gsub(/[\\%_]/) { |char| "\\#{char}" }}%")

  def period(from, to)
    parts = []
    parts << "X.data >= #{S.date(from)}" if from.present? && S.date(from) != 'NULL'
    parts << "X.data < DATE_ADD(#{S.date(to)}, INTERVAL 1 DAY)" if to.present? && S.date(to) != 'NULL'
    parts.presence&.join(' AND ')
  end

  # [[empresa, código], ...] — os clientes do ERP de um contato
  def clients(list)
    return if list.nil?
    return '1 = 0' if list.empty?

    parts = list.group_by(&:first).map do |company, rows|
      "(X.banco = #{S.str(company)} AND X.cliente_codigo IN (#{rows.map { |row| S.int(row.last) }.join(', ')}))"
    end
    "(#{parts.join(' OR ')})"
  end

  def view(definition, mine)
    return unless definition
    return "X.status IN (#{texts(definition[:status_in])})" if definition[:status_in]
    return "(X.status IS NULL OR X.status NOT IN (#{texts(definition[:status_not_in])}))" if definition[:status_not_in]
    return @kind.late_sql if definition[:late]

    mine_sql(mine) if definition[:mine]
  end

  def texts(list) = list.map { |item| S.str(item) }.join(', ')
  def mine_sql(mine) = mine ? "X.pessoa_codigo = #{S.int(mine)}" : '1 = 0'

  def person(code)
    "X.pessoa_codigo = #{S.int(code)}" if code.to_i.positive?
  end

  # { atendimento: 'GARANTIA', vendedor: 7 }: só os filtros que o tipo tem; texto compara sem espaço nas pontas
  def dimensions(values)
    parts = values.to_h.filter_map do |key, value|
      definition = @kind.dimensions[key.to_sym]
      next unless definition && value.present?
      next "#{dimension_value(definition)} = #{S.int(value)}" if definition[:numeric]

      "#{dimension_value(definition)} = #{S.str(value.to_s.strip.first(80))}"
    end
    parts.presence&.join(' AND ')
  end

  # código (vendedor sem código não conta) ou texto sem espaço nas pontas (vazio não conta)
  def dimension_value(definition)
    column = "X.#{definition[:column]}"
    definition[:numeric] ? "NULLIF(#{column}, 0)" : "NULLIF(TRIM(#{column}), '')"
  end
end
