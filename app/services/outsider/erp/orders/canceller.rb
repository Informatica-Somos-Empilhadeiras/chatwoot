# OUTSIDER: "Cancelar OS" de uma OS que o chat gravou (Outsider::Erp::OrderDraft): a única forma de desfazer, sem apagar
# nada. Muda a situação para CANCELADA pelas rotas oficiais do quadro de OS (troca + histórico, como o painel do ERP) e só
# se a OS ainda for a deste rascunho (marca) e estiver em NEGOCIAÇÃO. Numa OS convertida, o orçamento continua FECHADO e
# ligado a ela, como fica no Mais Prático quando o escritório cancela a OS.
class Outsider::Erp::Orders::Canceller
  class Invalid < StandardError; end

  CANCELLED = /\ACANCELAD/i

  def initialize(draft, user:)
    @draft = draft
    @user = user
    @settings = Outsider::Erp::Settings.new(draft.account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  def call
    # gravada, ou parada no meio com a OS já no ERP (o orçamento pode ter sido convertido no desktop nesse meio tempo)
    raise Invalid, 'not_created' unless @draft.in_erp? && !@draft.submitting?
    raise Invalid, 'cancelled' if @draft.cancelled?
    raise Invalid, 'usuario_erp' unless erp_user.positive?

    order = current_order
    raise Invalid, 'os_mudou' unless order
    raise Invalid, 'os_status' unless order['situacao'].to_s.strip.upcase == Outsider::Erp::Orders::Sql::NEGOTIATION

    write(cancelled_value)
    @draft.update_columns(erp_result: @draft.erp_result.to_h.merge('cancelled_at' => Time.current.iso8601, 'cancelled_by' => @user&.id), # rubocop:disable Rails/SkipsModelValidations
                          updated_at: Time.current)
    Rails.logger.info("[Outsider::Erp] conta #{@draft.account_id} usuário #{@user&.id} OS #{@draft.company}/#{@draft.erp_number} cancelada")
    @draft
  end

  private

  def erp_user = @settings.data['user_erp_ids'].to_h[@user&.id.to_s].to_i

  # a OS pelo número E pela marca: se o número não for mais desta OS, não mexe
  def current_order
    sql = Outsider::Erp::Orders::Sql.new(@draft, erp_user: erp_user)
    Array.wrap(@client.query_execute(sql.find_sql)).grep(Hash).find { |row| row['numero'].to_i == @draft.erp_number }
  end

  def cancelled_value
    Outsider::Erp::Lists.new(@draft.account).statuses.find { |value| value.to_s.strip.match?(CANCELLED) } || 'CANCELADA'
  rescue Outsider::Erp::Client::Error
    'CANCELADA'
  end

  def write(value)
    body = { 'listaEmpresas' => @settings.companies, 'Empresa' => @draft.company }
    @client.update('UpdateStatusOS', @draft.erp_number, body.merge('Situacao' => value))
    @client.update('GravaHistoricoStatusOS', @draft.erp_number, body.merge('Situacao' => value, 'idUsuario' => erp_user.to_s))
  end
end
