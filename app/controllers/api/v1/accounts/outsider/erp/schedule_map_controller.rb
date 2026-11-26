# OUTSIDER (Maps): "Mapa dos agendamentos" (Aplicativos > Google), ver Outsider::Erp::ScheduleMap. Pede "Vê" na linha
# "Mapa dos agendamentos" do perfil; gravar os campos vazios do cliente pede "Gravar no ERP" ligado e "Usa" na linha
# "Completar cadastro do cliente no ERP" (Outsider::Erp::ClientCompleter).
#   GET  erp/schedule_map            ?from=AAAA-MM-DD&to=AAAA-MM-DD&technician=&time_zone=   pontos dos clientes agendados
#   GET  erp/schedule_map/client     ?company=&code=        ficha, contatos, máquinas e OS abertas
#   POST erp/schedule_map/complete   { company, code, values: { campo: valor } }
class Api::V1::Accounts::Outsider::Erp::ScheduleMapController < Api::V1::Accounts::Outsider::Erp::BaseController
  MAX_DAYS = 62

  before_action :ensure_orders_enabled
  before_action :ensure_map_access
  before_action :ensure_complete_access, only: [:complete]

  def show
    from, to = period
    render json: map.points(from: from, to: to, technician: params[:technician].presence).merge(
      can_complete: complete_allowed?, map_id: ::Outsider::MapsSettings.new(Current.account).map_id
    )
  end

  def client
    company, code = target
    render json: map.client(company, code).merge(can_complete: complete_allowed?)
  end

  def complete
    company, code = target
    values = params.require(:values).permit(*::Outsider::Erp::ClientCompleter::FIELDS.keys).to_h
    render json: ::Outsider::Erp::ClientCompleter.new(Current.account).call(company, code, values)
  rescue ::Outsider::Erp::ClientCompleter::Disabled
    render json: { error: 'write_disabled' }, status: :forbidden
  end

  private

  def map = ::Outsider::Erp::ScheduleMap.new(Current.account)

  def period
    zone = ActiveSupport::TimeZone[params[:time_zone].to_s] || ActiveSupport::TimeZone['America/Sao_Paulo']
    from = day(params[:from]) || zone.today
    to = day(params[:to]) || (from + 7)
    to = from + MAX_DAYS if to - from > MAX_DAYS
    to = from if to < from
    [zone.parse(from.iso8601).beginning_of_day, zone.parse(to.iso8601).end_of_day]
  end

  def day(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def target
    company = params.require(:company).to_s
    code = Integer(params.require(:code).to_s, exception: false)
    raise ActionController::BadRequest, 'code' unless code&.positive? && settings.companies.include?(company)

    [company, code]
  end

  def complete_allowed? = settings.write_enabled? && allows_screen?('erp_client_complete', 'use')

  def ensure_map_access
    render json: { error: 'erp_forbidden' }, status: :forbidden unless allows_screen?('erp_schedule_map', 'view')
  end

  def ensure_complete_access
    render json: { error: 'erp_forbidden' }, status: :forbidden unless complete_allowed?
  end
end
