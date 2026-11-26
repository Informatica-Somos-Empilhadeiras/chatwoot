# OUTSIDER: "Liberar para separação" (o "Libera Conferência" do Mais Prático) pelo painel da OS: manda a OS para a fila de
# conferência do estoque. O ERP não tem função para isso; a gravação é a mesma que o Mais Prático deixa nas tabelas
# (Outsider::Erp::Orders::Conference): a hora da liberação em cada item e a OS em StatusSeparacao 2 com o dia. Só com a
# função ligada nas Configurações, na unidade liberada, com a OS em NEGOCIAÇÃO, com itens e ainda não liberada; confere
# lendo de volta. Nada é apagado.
class Outsider::Erp::Orders::Releaser
  S = Outsider::Erp::Sql
  class Invalid < StandardError; end
  class Disabled < StandardError; end

  RELEASED = 2

  def initialize(account, user:)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  def call(company, number)
    @company = company.to_s
    @number = number.to_i
    raise Disabled unless @settings.order_release_enabled? && @settings.order_company?(@company)

    order = current
    check!(order)
    write
    raise Invalid, 'not_saved' unless current['status'].to_i == RELEASED

    record(order)
  end

  private

  def check!(order)
    raise Invalid, 'not_found' unless order
    raise Invalid, 'os_status' unless order['situacao'].to_s.strip.upcase == Outsider::Erp::Orders::Sql::NEGOTIATION
    raise Invalid, 'already_released' unless order['status'].to_i.zero?
    raise Invalid, 'no_items' unless order['itens'].to_i.positive?
  end

  def current
    run('SELECT O.Situacao AS situacao, IFNULL(O.StatusSeparacao, 0) AS status, ' \
        "(SELECT COUNT(*) FROM #{table('detalheos')} D WHERE D.CodigoOS = O.CodigoOS) AS itens " \
        "FROM #{table('os')} O WHERE O.CodigoOS = #{S.int(@number)}").first
  end

  # itens primeiro (a hora), depois a OS, que só muda se ainda estiver em negociação e não liberada
  def write
    @client.query_execute("UPDATE #{table('detalheos')} SET DataSeparacao = NOW() WHERE CodigoOS = #{S.int(@number)}")
    @client.query_execute("UPDATE #{table('os')} SET StatusSeparacao = #{RELEASED}, DataSeparacao = CURDATE() " \
                          "WHERE CodigoOS = #{S.int(@number)} AND Situacao = #{S.str(Outsider::Erp::Orders::Sql::NEGOTIATION)} " \
                          'AND IFNULL(StatusSeparacao, 0) = 0')
  end

  def record(order)
    release = Outsider::Erp::OrderRelease.create!(account: @account, user: @user, company: @company, order_number: @number,
                                                  items_count: order['itens'].to_i)
    Rails.logger.info("[Outsider::Erp] conta #{@account.id} usuário #{@user&.id} OS #{@company}/#{@number} liberada para separação")
    release
  end

  def table(name) = "#{S.ident(@company)}.#{S.ident(name)}"
  def run(sql) = Array.wrap(@client.query_execute(sql)).grep(Hash)
end
