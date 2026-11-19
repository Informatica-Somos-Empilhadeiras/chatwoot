# OUTSIDER: nome do vendedor de um orçamento (vai embaixo da assinatura no PDF). Primeiro o cadastro de funcionários do
# ERP (as colunas que existirem); senão a pessoa do Chatwoot ligada a esse usuário do ERP nas Configurações.
class Outsider::Erp::SellerName
  S = Outsider::Erp::Sql
  CODE = %w[CodigoFuncionario Codigo CodFuncionario].freeze
  NAME = %w[Nome NomeFuncionario].freeze

  def initialize(account, client:)
    @account = account
    @client = client
    @schema = Outsider::Erp::Schema.new(account, client: client)
    @settings = Outsider::Erp::Settings.new(account)
  end

  def for_code(company, code)
    return if code.to_i <= 0

    from_erp(company, code).presence || from_settings(code)
  end

  private

  def from_erp(company, code)
    code_column = @schema.pick(company, 'funcionarios', CODE)
    name_column = @schema.pick(company, 'funcionarios', NAME)
    return unless code_column && name_column

    sql = "SELECT F.#{S.column(name_column)} AS nome FROM #{S.ident(company)}.funcionarios F WHERE F.#{S.column(code_column)} = #{S.int(code)}"
    @client.query_execute(sql).grep(Hash).first.to_h['nome'].to_s.squish
  rescue Outsider::Erp::Client::Error
    nil
  end

  def from_settings(code)
    user_id = @settings.data['user_erp_ids'].to_h.key(code.to_s)
    user_id && @account.users.find_by(id: user_id)&.name
  end
end
