# OUTSIDER: "Cadastrar cliente no ERP" pelo chat. Grava SÓ pelas funções do próprio Mais Prático (as mesmas do app
# mobile deles), via query_execute e sempre com o banco da unidade como prefixo:
# - sp_CadastraCliente: o cliente entra como pré-cadastro (PreCadastro = 1, Ativo = 1), que o escritório completa (a
#   função não preenche município, perfil nem cadastro). Com o mesmo CPF/CNPJ já gravado, ela devolve o código existente;
# - sp_CadastraEnderecoCliente: copia o endereço para cobrança e entrega, só no cliente que esta tela acabou de criar
#   (conferido pela chave CodigoIntegracaoMobile), nunca num que já existia.
#
# Antes de gravar: gravação ligada nas Configurações (desligada por padrão), unidade da lista das Configurações, dados
# conferidos (Outsider::Erp::ClientForm) e CPF/CNPJ procurado sem máscara (a função só acha o texto exato; assim não
# nasce cliente repetido). Um cadastro por vez por unidade (trava no Redis): a função usa MAX(CodigoCliente) + 1.
class Outsider::Erp::ClientRegistrar
  class Disabled < StandardError; end

  class Invalid < StandardError
    attr_reader :fields

    def initialize(reason, fields = [])
      @fields = fields
      super(reason)
    end
  end

  S = Outsider::Erp::Sql
  TABLE = 'clientes'.freeze
  LOCK_SECONDS = 60
  KEY_PREFIX = 'CWC'.freeze
  ADDRESS_TYPES = %w[COBRANCA ENTREGA].freeze
  CLEAN_DOCUMENT = "UPPER(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(%s), '.', ''), '/', ''), '-', ''), ' ', ''))".freeze

  def initialize(account, user:, client: nil)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
    @client = client || Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(account, client: @client)
  end

  # { 'empresa', 'codigo', 'nome', 'documento', 'existente', 'vinculado' }
  def call(params, contact: nil)
    params = params.to_h.stringify_keys
    company = company!(params['company'])
    form = Outsider::Erp::ClientForm.new(params)
    raise Invalid.new('dados', form.errors) unless form.valid?

    with_lock(company) do
      result = existing(company, form.document)&.merge('existente' => true) || create(company, form)
      result.merge('vinculado' => link(contact, result))
    end
  end

  # cliente da unidade com este CPF/CNPJ (com ou sem máscara), ou nil
  def existing(company, document)
    company = company!(company)
    document = Outsider::Erp::ClientForm.clean_document(document)
    return unless Outsider::Erp::ClientForm.valid_document?(document)

    column = @schema.pick(company, TABLE, %w[CPF_CNPJ])
    return unless column

    sql = "SELECT #{@schema.select_list(company, TABLE, 'C', 'codigo' => %w[CodigoCliente], 'nome' => %w[Nome], 'documento' => %w[CPF_CNPJ])} " \
          "FROM #{S.ident(company)}.#{TABLE} C WHERE #{format(CLEAN_DOCUMENT, "C.#{S.column(column)}")} = #{S.str(document)} " \
          'ORDER BY codigo LIMIT 1'
    row = @client.query_execute(sql).grep(Hash).first
    row && { 'empresa' => company, 'codigo' => row['codigo'].to_i, 'nome' => row['nome'].to_s.squish, 'documento' => row['documento'] }
  end

  private

  def company!(company)
    raise Disabled unless @settings.client_write_enabled?
    raise Invalid, 'empresa' unless @settings.companies.include?(company.to_s)

    company.to_s
  end

  def with_lock(company)
    key = "outsider_erp:#{@account.id}:client_lock:#{company}"
    raise Invalid, 'em_andamento' unless Redis::Alfred.set(key, '1', nx: true, ex: LOCK_SECONDS)

    begin
      yield
    ensure
      Redis::Alfred.delete(key)
    end
  end

  def create(company, form)
    profile = Outsider::Erp::ClientProfile.new(@account, company, client: @client)
    values = Outsider::Erp::ClientValues.new(form, profile, key: "#{KEY_PREFIX}#{SecureRandom.alphanumeric(9).upcase}", author: @user&.name)
    code = scalar(@client.query_execute(client_sql(company, values)))
    raise Invalid, 'documento' if code == -999
    raise Invalid, 'sem_codigo' unless code.positive?

    created = created?(company, code, values['chave'])
    log("#{created ? 'cliente criado' : 'cliente já existia'} #{company}/#{code}")
    after_create(company, code, values, form) if created
    { 'empresa' => company, 'codigo' => code, 'nome' => values['nome'], 'documento' => values['documento'], 'existente' => !created }
  end

  # só no cliente que esta tela criou: endereço de cobrança e entrega e a lista de clientes da tela
  def after_create(company, code, values, form)
    copy_address(company, code, values) if form.copy_address? && form.address?
    remember(company, code, values)
  end

  # SELECT <banco>.sp_CadastraCliente(...): a ordem é a dos parâmetros da função. O contato vai como 1 e 2 (compras e
  # faturamento): a função grava o segundo sempre que o primeiro tem nome
  def client_sql(company, values)
    contact = %w[contato_nome contato_email contato_telefone].map { |key| S.str(values[key]) }
    args = [S.int(values['tipo']), *%w[nome apelido documento rg_ie endereco numero bairro referencia cep uf cidade telefone celular email
                                       observacoes].map { |key| S.str(values[key]) },
            S.int(values['vendedor']), S.int(0), *contact, *contact, S.str(values['chave'])]
    "SELECT #{S.ident(company)}.sp_CadastraCliente(#{args.join(', ')}) AS codigo"
  end

  # a chave que esta tela mandou está no cliente devolvido: foi ela que criou (senão a função achou um já existente)
  def created?(company, code, key)
    column = @schema.pick(company, TABLE, %w[CodigoIntegracaoMobile])
    return false unless column

    sql = "SELECT C.#{S.column(column)} AS chave FROM #{S.ident(company)}.#{TABLE} C " \
          "WHERE C.#{S.column(@schema.pick(company, TABLE, %w[CodigoCliente]))} = #{S.int(code)} LIMIT 1"
    @client.query_execute(sql).grep(Hash).first&.dig('chave').to_s == key
  end

  def copy_address(company, code, values)
    address = %w[endereco numero bairro referencia cep uf cidade].map { |key| S.str(values[key]) }
    ADDRESS_TYPES.each do |type|
      @client.query_execute("SELECT #{S.ident(company)}.sp_CadastraEnderecoCliente(#{S.int(code)}, #{S.str(values['documento'])}, " \
                            "#{S.str(type)}, #{address.join(', ')}) AS codigo")
    end
  end

  def link(contact, result)
    return false unless contact

    Outsider::Erp::ContactLink.new(contact).add(company: result['empresa'], code: result['codigo'], name: result['nome'], settings: @settings)
    true
  end

  # a lista de clientes da tela já traz o novo (sem esperar a próxima busca completa)
  def remember(company, code, values)
    Outsider::Erp::Customers.new(@account).remember(
      company, 'codigo' => code, 'nome' => values['nome'], 'fantasia' => values['apelido'], 'documento' => values['documento'],
               'cidade' => values['cidade'], 'uf' => values['uf'], 'fone0' => values['telefone'], 'fone1' => values['celular']
    )
  end

  def scalar(rows)
    row = rows.is_a?(Array) ? rows.first : rows
    Integer((row.is_a?(Hash) ? row.values.first : row).to_s, exception: false).to_i
  end

  def log(text)
    Rails.logger.info("[Outsider::Erp] conta #{@account.id} usuário #{@user&.id}: #{text}")
  end
end
