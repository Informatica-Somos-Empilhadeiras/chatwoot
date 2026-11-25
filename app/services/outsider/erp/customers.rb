# OUTSIDER: a lista de clientes do ERP (tabela clientes de cada unidade da Somos), para o agente vincular um contato
# escolhendo numa lista em vez de digitar. Cópia curta no Redis (Outsider::Erp::Snapshot, renovada pelo Sidekiq a cada
# 30 min): abrir o painel não chama o ERP. Só leitura, via query_execute, sempre com o banco da unidade como prefixo.
#
# As colunas vêm do information_schema (Outsider::Erp::Schema): nome, fantasia, CPF/CNPJ, cidade, UF e os telefones,
# os que existirem. Os telefones só servem para sugerir o cliente de um contato; não vão para a tela.
class Outsider::Erp::Customers
  S = Outsider::Erp::Sql
  TABLE = 'clientes'.freeze
  TTL = 30.minutes
  MAX_ROWS = 20_000
  LIMIT = 40
  SUGGESTIONS = 5
  PHONE_MATCH = 100
  NAME_MATCH = 50
  # chave na resposta => colunas candidatas (vale a primeira que existir na unidade)
  COLUMNS = {
    'codigo' => %w[CodigoCliente], 'nome' => %w[Nome RazaoSocial NomeCliente Razao], 'fantasia' => %w[Fantasia NomeFantasia Apelido],
    'documento' => %w[CPF_CNPJ CNPJ_CPF CNPJ CPF], 'cidade' => %w[Cidade Municipio NomeCidade], 'uf' => %w[UF Estado]
  }.freeze
  REQUIRED = %w[codigo nome].freeze
  PHONE = /fone|celular|whats|\Atel/i
  MAX_PHONES = 4
  PUBLIC = %w[empresa codigo nome fantasia documento cidade uf].freeze

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
  end

  def snapshot
    @snapshot ||= Outsider::Erp::Snapshot.new(@account, 'customers', ttl: TTL.to_i, loader: method(:load), sync: false)
  end

  # cliente sem nome no ERP (só o código, às vezes o CPF/CNPJ) não entra na lista; sem razão social, vale o fantasia
  def rows
    items = snapshot.fetch['items'].filter_map { |row| named(row) }
    @only_company ? items.select { |row| row['empresa'] == @only_company } : items
  end

  # a lista da tela: sem filtro e com um contato, os parecidos com ele vêm primeiro (marcados com o motivo).
  # company: só os clientes dessa unidade (o orçamento escolhe a unidade antes do cliente)
  def list(query, contact: nil, company: nil)
    @only_company = company.presence
    return search(query) if query.present? || contact.nil?

    top = suggestions(contact)
    seen = top.to_set { |row| [row['empresa'], row['codigo']] }
    (top + search('').reject { |row| seen.include?([row['empresa'], row['codigo']]) }).first(LIMIT)
  end

  # filtro por nome/fantasia (todas as palavras), código ou CPF/CNPJ (só números). A cópia já vem em ordem alfabética.
  def search(query, limit: LIMIT)
    query = query.to_s.strip
    return rows.first(limit).map { |row| row.slice(*PUBLIC) } if query.empty?

    rows.select { |row| match?(row, query) }.sort_by { |row| rank(row, query) }.first(limit).map { |row| row.slice(*PUBLIC) }
  end

  # clientes parecidos com o contato: o mesmo telefone (final de 8 dígitos) ou o nome da empresa/pessoa
  def suggestions(contact)
    phones = phone_keys(contact.phone_number)
    names = name_words(contact)
    scored = rows.filter_map do |row|
      score = similarity(row, phones, names)
      [score, row] if score.positive?
    end
    scored.sort_by { |score, row| [-score, row['nome'].to_s] }.first(SUGGESTIONS).map do |score, row|
      row.slice(*PUBLIC).merge('motivo' => score >= PHONE_MATCH ? 'telefone' : 'nome')
    end
  end

  # cliente que a tela acabou de cadastrar no ERP (Outsider::Erp::ClientRegistrar): entra na cópia na hora
  def remember(company, data)
    row = build(company, data)
    snapshot.update_items do |items|
      (items.reject { |item| item['empresa'] == company && item['codigo'] == row['codigo'] } + [row]).sort_by { |item| item['busca'] }
    end
  end

  private

  def load(read_timeout)
    client = Outsider::Erp::Client.new(@settings)
    schema = Outsider::Erp::Schema.new(@account, client: client)
    @settings.companies.flat_map { |company| load_company(client, schema, company, read_timeout) }.sort_by { |row| row['busca'] }
  end

  def load_company(client, schema, company, read_timeout)
    picked = COLUMNS.transform_values { |names| schema.pick(company, TABLE, names) }.compact
    return [] unless REQUIRED.all? { |key| picked.key?(key) }

    phones = schema.columns(company, TABLE).grep(PHONE).first(MAX_PHONES)
    client.query_execute(select_sql(company, picked, phones), read_timeout: read_timeout).grep(Hash).map { |data| build(company, data) }
  end

  def named(row)
    name = row['nome'].presence || row['fantasia'].presence
    name && row.merge('nome' => name)
  end

  def select_sql(company, picked, phones)
    fields = picked.map { |key, column| "T.#{S.column(column)} AS #{key}" } +
             phones.each_with_index.map { |column, index| "T.#{S.column(column)} AS fone#{index}" }
    "SELECT #{fields.join(', ')} FROM #{S.ident(company)}.#{TABLE} T ORDER BY T.#{S.column(picked['nome'])} LIMIT #{MAX_ROWS}"
  end

  # busca e fones já prontos na cópia: filtrar milhares de clientes fica barato
  def build(company, data)
    row = { 'empresa' => company, 'codigo' => data['codigo'].to_i, 'nome' => data['nome'].to_s.squish }
    %w[fantasia documento cidade uf].each { |key| row[key] = data[key].to_s.squish.presence }
    row.merge('busca' => normalize("#{row['nome']} #{row['fantasia']}"),
              'fones' => data.select { |key, _| key.start_with?('fone') }.values.flat_map { |value| phone_keys(value) }.uniq)
  end

  def match?(row, query)
    return number_match?(row, query.gsub(/\D/, '')) if query.match?(%r{\A[\d\s./-]+\z})

    words?(row, normalize(query).split)
  end

  # só números: o código do cliente ou parte do CPF/CNPJ (a partir de 4 dígitos)
  def number_match?(row, digits)
    row['codigo'].to_s == digits || (digits.length >= 4 && row['documento'].to_s.gsub(/\D/, '').include?(digits))
  end

  def similarity(row, phones, names)
    score = phones.intersect?(row['fones'].to_a) ? PHONE_MATCH : 0
    names.any? { |words| words?(row, words) } ? score + NAME_MATCH : score
  end

  def words?(row, words)
    words.any? && words.all? { |word| row['busca'].include?(word) }
  end

  # código exato primeiro, depois quem começa com o texto, depois em ordem alfabética
  def rank(row, query)
    text = normalize(query)
    [row['codigo'].to_s == query ? 0 : 1, text.present? && row['busca'].start_with?(text) ? 0 : 1, row['nome'].to_s]
  end

  # nome da empresa do contato e, se tiver ao menos duas palavras, o nome dele (um primeiro nome sozinho casa com muitos)
  def name_words(contact)
    company = Outsider::Erp::ServiceOrders.words(contact.additional_attributes.to_h['company_name'])
    person = Outsider::Erp::ServiceOrders.words(contact.name)
    [company, person.size >= 2 ? person : []].reject(&:empty?)
  end

  # um telefone pode vir com DDI/DDD e máscara; compara os 8 últimos dígitos (vários números num campo só também valem)
  def phone_keys(value)
    value.to_s.split(%r{[/;,]|\s{2,}}).filter_map do |part|
      digits = part.gsub(/\D/, '')
      digits.last(8) if digits.length >= 8
    end
  end

  def normalize(text) = Outsider::Erp::ServiceOrders.normalize(text)
end
