# OUTSIDER: confere no ERP o código e a senha de quem libera um desconto acima do limite (Outsider::Erp::DiscountPolicy).
# A senha não é guardada nem vai para o log, e não sai do servidor em texto: o ERP guarda as senhas como resumo MD5
# (32 caracteres hex em todos os funcionários), então a consulta leva só o resumo e devolve a pessoa apenas se ele bater.
# A coluna da senha nunca é lida. Pode liberar quem tem a permissão de desconto do ERP (ac_desconto, inclusão) ou é
# gerente. Tentativas erradas são limitadas por pessoa do chat e por código do ERP.
class Outsider::Erp::DiscountApprover
  class Refused < StandardError; end

  S = Outsider::Erp::Sql
  USER_TRIES = 5
  USER_WINDOW = 15.minutes
  CODE_TRIES = 10
  CODE_WINDOW = 1.hour
  MANAGER = %w[Gerente gerenteComercial CargoGerente].freeze
  MAX_PASSWORD = 64

  def initialize(account_user, client: nil)
    @account_user = account_user
    @account = account_user.account
    @settings = Outsider::Erp::Settings.new(@account)
    @client = client || Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(@account, client: @client)
  end

  # { code:, name: } de quem liberou; Refused com o motivo (código, senha, tentativas, permissão)
  def verify(company, code, password)
    code = check!(company, code, password)
    row = lookup(company, code, password.to_s)
    return failed!(company, code) unless row
    raise Refused, 'sem_permissao' unless row['gerente'].to_i.positive? || row['ac_desconto'].to_i.positive?

    Redis::Alfred.delete(user_key)
    { code: code, name: row['nome'].to_s.squish }
  end

  private

  def check!(company, code, password)
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company)

    code = Integer(code.to_s, exception: false)
    raise Refused, 'codigo_gerente' unless code&.between?(1, 999_999_999)
    raise Refused, 'senha_gerente' if password.to_s.empty? || password.to_s.size > MAX_PASSWORD
    raise Refused, 'tentativas' if locked?(company, code)

    code
  end

  def lookup(company, code, password)
    code_column = @schema.pick(company, 'funcionarios', Outsider::Erp::SellerName::CODE)
    name_column = @schema.pick(company, 'funcionarios', Outsider::Erp::SellerName::NAME)
    password_column = @schema.pick(company, 'funcionarios', %w[Senha])
    raise Refused, 'sem_cadastro' unless code_column && name_column && password_column

    bank = S.ident(company)
    sql = "SELECT L.#{S.column(name_column)} AS nome, #{manager_sql(company)} AS gerente, #{permission_sql(company, bank, code)} AS ac_desconto " \
          "FROM #{bank}.funcionarios L WHERE L.#{S.column(code_column)} = #{S.int(code)} " \
          "AND LOWER(L.#{S.column(password_column)}) IN (#{digests(password).map { |item| S.str(item) }.join(', ')})"
    @client.query_execute(sql, read_timeout: 15).grep(Hash).first
  end

  def manager_sql(company)
    columns = MANAGER.filter_map { |name| @schema.pick(company, 'funcionarios', [name]) }
    return '0' if columns.empty?

    "(#{columns.map { |column| "IFNULL(L.#{S.column(column)}, 0) = 1" }.join(' OR ')})"
  end

  def permission_sql(company, bank, code)
    return '0' unless @schema.pick(company, 'ac_desconto', %w[Funcionario]) && @schema.pick(company, 'ac_desconto', %w[Inclusao])

    "(SELECT COUNT(*) FROM #{bank}.ac_desconto A WHERE A.`Funcionario` = #{S.int(code)} AND A.`Inclusao` = 1)"
  end

  # resumo MD5 como o ERP guarda: o texto digitado (UTF-8 e Windows-1252, que é o do sistema) e em maiúsculas
  def digests(password)
    variants = [password, password.upcase]
    ansi = variants.filter_map { |text| text.encode('Windows-1252', invalid: :replace, undef: :replace).b }
    (variants + ansi).map { |text| Digest::MD5.hexdigest(text) }.uniq
  end

  def failed!(company, code)
    bump(user_key, USER_WINDOW)
    bump(code_key(company, code), CODE_WINDOW)
    raise Refused, 'senha_invalida'
  end

  def locked?(company, code)
    Redis::Alfred.get(user_key).to_i >= USER_TRIES || Redis::Alfred.get(code_key(company, code)).to_i >= CODE_TRIES
  end

  def bump(key, window)
    Redis::Alfred.expire(key, window.to_i) if Redis::Alfred.incr(key) == 1
  end

  def user_key = "outsider_erp:#{@account.id}:discount_tries:user:#{@account_user.user_id}"
  def code_key(company, code) = "outsider_erp:#{@account.id}:discount_tries:code:#{company}:#{code}"
end
