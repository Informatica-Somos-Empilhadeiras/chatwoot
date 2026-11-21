# OUTSIDER: como cada unidade do ERP cadastra cliente, lido dos próprios dados (só leitura, sempre com o banco da unidade
# como prefixo), para o pré-cadastro feito no chat sair igual aos do escritório:
# - CPF/CNPJ e CEP com ou sem máscara (a função do Mais Prático só acha um cliente repetido pelo texto exato);
# - o número do TipoPessoa de pessoa física e de jurídica (o mais usado nos CPFs e nos CNPJs já cadastrados);
# - nomes em maiúsculas ou não;
# - o tamanho de cada campo (o menor entre o parâmetro da função e a coluna), para nunca estourar.
# Fica no Redis por um dia.
class Outsider::Erp::ClientProfile
  S = Outsider::Erp::Sql
  TTL = 1.day
  SAMPLE = 300
  SAMPLE_COLUMNS = { 'documento' => %w[CPF_CNPJ], 'tipo' => %w[TipoPessoa], 'nome' => %w[Nome], 'cep' => %w[Cep] }.freeze
  FUNCTIONS = %w[sp_CadastraCliente sp_CadastraEnderecoCliente].freeze
  TABLES = %w[clientes contatosclientes].freeze
  # campo do formulário => parâmetros das funções e colunas que recebem o valor (clientes.* e contatosclientes.*)
  FIELDS = {
    'nome' => [%w[v_nome], %w[clientes.nome]], 'apelido' => [%w[v_apelido], %w[clientes.apelido]],
    'documento' => [%w[v_cpfcnpj], %w[clientes.cpf_cnpj]], 'rg_ie' => [%w[v_rgie], %w[clientes.rgie]],
    'endereco' => [%w[v_endereco], %w[clientes.endereco clientes.enderecocob clientes.enderecoentr]],
    'numero' => [%w[v_numero], %w[clientes.numero clientes.numerocob clientes.numeroentr]],
    'bairro' => [%w[v_bairro], %w[clientes.bairro clientes.bairrocob clientes.bairroentr]],
    'referencia' => [%w[v_referencia], %w[clientes.referencia clientes.referenciacob clientes.referenciaentr]],
    'cep' => [%w[v_cep], %w[clientes.cep clientes.cepcob clientes.cepentr]],
    'uf' => [%w[v_uf], %w[clientes.uf clientes.ufcob clientes.ufentr]],
    'cidade' => [%w[v_cidade], %w[clientes.cidade clientes.cidadecob clientes.cidadeentr]],
    'telefone' => [%w[v_tel], %w[clientes.telresidencia]], 'celular' => [%w[v_cel], %w[clientes.celular]],
    'email' => [%w[v_email], %w[clientes.email]], 'observacoes' => [%w[v_obs], %w[clientes.observacoes]],
    'contato_nome' => [%w[v_contatonome1 v_contatonome2], %w[contatosclientes.nome]],
    'contato_email' => [%w[v_contatoemail1 v_contatoemail2], %w[contatosclientes.email]],
    'contato_telefone' => [%w[v_contatotelefone1 v_contatotelefone2], %w[contatosclientes.fone]],
    'chave' => [%w[v_codigomobile], %w[clientes.codigointegracaomobile]]
  }.freeze
  CNPJ_SIZE = 14
  CPF_SIZE = 11

  def initialize(account, company, client:)
    @account = account
    @company = company
    @client = client
  end

  def masked_document? = data['documento_mascara'] == true
  def masked_cep? = data['cep_mascara'] == true
  def uppercase? = data['maiusculas'] == true
  # TipoPessoa do ERP para 'F' ou 'J'
  def person_code(person) = data['tipo'][person].to_i
  # tamanho máximo de um campo do formulário nesta unidade (nil = sem limite conhecido)
  def limit(field) = data['limites'][field]

  def data
    @data ||= cached { { 'limites' => limits }.merge(habits) }
  end

  private

  def cached
    key = "outsider_erp:#{@account.id}:client_profile:#{@company}"
    raw = Redis::Alfred.get(key)
    return JSON.parse(raw) if raw

    yield.tap { |value| Redis::Alfred.set(key, value.to_json, ex: TTL.to_i) }
  end

  def habits
    rows = @client.query_execute(sample_sql).grep(Hash)
    {
      'documento_mascara' => majority?(rows, 'documento') { |value| value.match?(%r{[./-]}) },
      'cep_mascara' => majority?(rows, 'cep') { |value| value.include?('-') },
      'maiusculas' => majority?(rows, 'nome') { |value| value == value.upcase },
      'tipo' => person_codes(rows)
    }
  end

  def sample_sql
    schema = Outsider::Erp::Schema.new(@account, client: @client)
    document = schema.pick(@company, 'clientes', %w[CPF_CNPJ])
    raise Outsider::Erp::Client::Error, 'clientes sem CPF_CNPJ' unless document

    list = schema.select_list(@company, 'clientes', 'C', SAMPLE_COLUMNS)
    "SELECT #{list} FROM #{S.ident(@company)}.clientes C WHERE C.#{S.column(document)} IS NOT NULL " \
      "AND C.#{S.column(document)} <> '' ORDER BY C.#{S.column(schema.pick(@company, 'clientes', %w[CodigoCliente]))} DESC LIMIT #{SAMPLE}"
  end

  # a maioria dos valores preenchidos dessa coluna é assim
  def majority?(rows, key, &)
    values = rows.map { |row| row[key].to_s.strip }.compact_blank
    values.any? && values.count(&) * 2 >= values.size
  end

  # o TipoPessoa mais usado nos CNPJs e nos CPFs; sem nenhum de um dos lados, o outro número (0/1)
  def person_codes(rows)
    by_size = rows.group_by { |row| Outsider::Erp::ClientForm.clean_document(row['documento']).size }
    company = most_common(by_size[CNPJ_SIZE])
    person = most_common(by_size[CPF_SIZE])
    company ||= person.nil? ? 1 : 1 - person.clamp(0, 1)
    person ||= company.zero? ? 1 : 0
    { 'J' => company, 'F' => person }
  end

  def most_common(rows)
    codes = Array(rows).filter_map { |row| Integer(row['tipo'].to_s, exception: false) }
    codes.tally.max_by { |_, count| count }&.first
  end

  # menor tamanho entre os parâmetros das duas funções e as colunas que recebem cada campo
  def limits
    params = sizes(params_sql)
    columns = sizes(columns_sql)
    FIELDS.transform_values do |(names, targets)|
      (names.filter_map { |name| params[name] } + targets.filter_map { |name| columns[name] }).min
    end.compact
  end

  def sizes(sql)
    @client.query_execute(sql).grep(Hash).each_with_object({}) do |row, out|
      size = row['tamanho'].to_i
      name = row['nome'].to_s.downcase
      out[name] = [out[name], size].compact.min if size.positive?
    end
  end

  def params_sql
    'SELECT PARAMETER_NAME AS nome, CHARACTER_MAXIMUM_LENGTH AS tamanho FROM information_schema.PARAMETERS ' \
      "WHERE SPECIFIC_SCHEMA = #{S.str(@company)} AND SPECIFIC_NAME IN (#{FUNCTIONS.map { |name| S.str(name) }.join(', ')}) " \
      'AND CHARACTER_MAXIMUM_LENGTH IS NOT NULL'
  end

  def columns_sql
    "SELECT CONCAT(LOWER(TABLE_NAME), '.', LOWER(COLUMN_NAME)) AS nome, CHARACTER_MAXIMUM_LENGTH AS tamanho " \
      "FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = #{S.str(@company)} " \
      "AND LOWER(TABLE_NAME) IN (#{TABLES.map { |name| S.str(name) }.join(', ')}) AND CHARACTER_MAXIMUM_LENGTH IS NOT NULL"
  end
end
