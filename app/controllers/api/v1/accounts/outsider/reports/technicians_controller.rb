# OUTSIDER: relatório de desempenho dos técnicos (aba de relatório da seção ERP, Outsider::Erp::TechnicianReport). Ver
# pede a linha "Desempenho dos técnicos" do perfil de acesso; a comissão e as metas só o administrador muda.
class Api::V1::Accounts::Outsider::Reports::TechniciansController < Api::V1::Accounts::BaseController
  before_action :ensure_erp
  before_action :ensure_report_access
  before_action :ensure_admin, only: :update

  rescue_from(ArgumentError, Date::Error) { |error| render json: { error: 'invalid', field: error.message }, status: :unprocessable_entity }
  rescue_from(::Outsider::Erp::Client::Error) do |error|
    render json: { error: 'erp_unavailable', message: error.message }, status: :service_unavailable
  end
  rescue_from(::Outsider::Erp::Settings::Invalid) { |error| render json: { error: 'invalid', fields: error.errors }, status: :unprocessable_entity }

  # from/to (data da nota, aaaa-mm-dd; padrão: o mês atual) e companies[] (padrão: todas as unidades)
  def show
    from = date(:from, Date.current.beginning_of_month)
    to = date(:to, Date.current)
    report = ::Outsider::Erp::TechnicianReport.new(Current.account).build(from: from, to: to, companies: Array(params[:companies]).map(&:to_s))
    render json: report.merge('pode_configurar' => Current.account_user.administrator?, 'metas' => settings.report_goals,
                              'tipos_fora_da_soma' => settings.report_excluded_types)
  end

  # report_commission_pct, report_goals ({ "NOME" => meta em R$ }) e report_excluded_types (tipos de atendimento fora da soma)
  def update
    settings.update(params.permit(:report_commission_pct, report_goals: {}, report_excluded_types: []).to_h)
    render json: { comissao_pct: settings.report_commission_pct, metas: settings.report_goals, tipos_fora_da_soma: settings.report_excluded_types }
  end

  private

  def date(key, fallback) = params[key].present? ? Date.iso8601(params[key].to_s) : fallback

  def settings = @settings ||= ::Outsider::Erp::Settings.new(Current.account)

  def ensure_erp
    render json: { error: 'erp_disabled' }, status: :forbidden unless settings.enabled?
  end

  def ensure_report_access
    allowed = ::Outsider::Access.for(Current.account_user).allows?('reports_technicians', 'view')
    render json: { error: 'reports_forbidden' }, status: :forbidden unless allowed
  end

  def ensure_admin
    render json: { error: 'reports_admin_only' }, status: :forbidden unless Current.account_user.administrator?
  end
end
