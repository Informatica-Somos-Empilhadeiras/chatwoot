# OUTSIDER: o técnico e o "Enviar para o app do técnico" de uma OS, escolhidos no Agendar (Outsider::Erp::OrderScheduler),
# como o agendador do quadro de OS do Mais Prático (saíram da Nova OS e da conversão). O técnico vai pela rota oficial do
# quadro (Outsider::Erp::Writer#technician); o envio para o app grava os mesmos campos que o desktop deixa nas OS enviadas
# ao celular (ExibirFSMMobile e o sub status do app), só com técnico na OS, e confere lendo de volta. Tudo só com
# "Gravar no ERP" ligado; uma falha aqui nunca derruba o agendamento (o evento já está na agenda).
class Outsider::Erp::Orders::Assignment
  S = Outsider::Erp::Sql

  def initialize(account, user)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
  end

  # => { technician: { ok, reason?, name? }, app: { ok, reason? } } (só as partes pedidas)
  def call(company, number, technician:, app:)
    steps = { technician: technician.to_i.positive?, app: app == true }.select { |_, wanted| wanted }.keys
    return steps.index_with { skipped } unless @settings.write_enabled?

    result = {}
    result[:technician] = assign(company, number, technician.to_i) if steps.include?(:technician)
    # o app só com o técnico escolhido gravado (senão a OS iria para o app do técnico antigo)
    if steps.include?(:app)
      result[:app] =
        result.dig(:technician, :ok) == false ? { ok: false, reason: 'technician_failed' } : send_to_app(company, number)
    end
    result
  end

  private

  def skipped = { ok: false, reason: 'write_disabled' }

  def assign(company, number, code)
    name = Outsider::Erp::Lists.new(@account).technicians.find { |row| row[:codigo].to_i == code }&.dig(:nome)
    return { ok: false, reason: 'not_technician' } unless name

    return { ok: true, name: name } if current(company, number)['tecnico'].to_i == code

    writer.technician(company: company, code: number, tecnico_id: code, tecnico_name: name)
    { ok: true, name: name }
  rescue StandardError => e
    failed('técnico', e)
  end

  def send_to_app(company, number)
    order = current(company, number)
    return { ok: false, reason: 'no_technician' } unless order['tecnico'].to_i.positive?
    return { ok: true } if order['app'].to_i == 1

    client.query_execute("UPDATE #{S.ident(company)}.os SET ExibirFSMMobile = 1, SubStatusFSM = " \
                         "#{S.str(Outsider::Erp::Orders::Sql::APP_SUBSTATUS)} WHERE CodigoOS = #{S.int(number)} AND IFNULL(Tecnico, 0) > 0")
    current(company, number)['app'].to_i == 1 ? { ok: true } : { ok: false, reason: 'not_saved' }
  rescue StandardError => e
    failed('app do técnico', e)
  end

  def current(company, number)
    Array.wrap(client.query_execute("SELECT O.Tecnico AS tecnico, O.ExibirFSMMobile AS app FROM #{S.ident(company)}.os O " \
                                    "WHERE O.CodigoOS = #{S.int(number)}")).grep(Hash).first.to_h
  end

  def failed(what, error)
    Rails.logger.info("[Outsider::Erp] agendar OS sem #{what}: #{error.class} #{error.message}")
    { ok: false, reason: 'failed' }
  end

  def writer = @writer ||= Outsider::Erp::Writer.new(account: @account, user: @user)
  def client = @client ||= Outsider::Erp::Client.new(@settings)
end
