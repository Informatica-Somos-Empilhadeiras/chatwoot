# OUTSIDER: ligações da Telefonia (Entrega 22): lista com filtros, a fila de retorno e o painel
# (Outsider::Voice::Wallboard, Entrega 23). Cada pessoa vê o que Outsider::Voice::CallAccess deixa.
# Entrega 24: mês e horas no fuso da telefonia, exportação (planilhas e PDF) e as gravações.
class Api::V1::Accounts::Outsider::Crm::CallsController < Api::V1::Accounts::Outsider::Crm::BaseController
  PER_PAGE = 50
  FILTERS = %w[direction status user_id].freeze

  def index
    calls = filtered.includes(:user, :contact, :returned_by, recording_attachment: :blob).order(started_at: :desc)
    page = [params[:page].to_i, 1].max
    render json: { payload: calls.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map { |call| call_json(call) },
                   meta: { page: page, per_page: PER_PAGE, total: calls.count } }
  end

  # painel da Telefonia (Entrega 23)
  def wallboard
    render json: board.to_h
  end

  # Entrega 24. kind: pdf (relatório do painel), calls, agents ou days (planilhas). source=history: a lista de
  # Ligações com os filtros da tela; senão, o período e o vendedor do painel
  def export
    return export_pdf if params[:kind] == 'pdf'

    csv = ::Outsider::Voice::ReportCsv.new(settings.time_zone)
    data = case params[:kind]
           when 'agents' then csv.agents(crm_access.manager? ? board.agents : [])
           when 'days' then csv.days(board.timeline)
           else csv.calls(params[:source] == 'history' ? filtered.order(started_at: :desc) : board_calls)
           end
    send_data data, filename: "#{export_name}.csv", type: 'text/csv; charset=utf-8'
  end

  # gravação apagada pelo administrador (Entrega 24)
  def destroy_recording
    return render_forbidden unless crm_access.administrator?

    call = ::Outsider::Voice::Call.find_by!(account_id: Current.account.id, id: params[:id])
    call.recording.purge_later
    head :no_content
  end

  private

  def settings
    @settings ||= ::Outsider::Voice::Settings.new(Current.account)
  end

  def board
    @board ||= ::Outsider::Voice::Wallboard.new(crm_access, period: params[:period], user_id: params[:user_id], from: params[:from], to: params[:to])
  end

  def board_calls
    ::Outsider::Voice::Call.where(id: board.calls.map(&:id)).order(:started_at)
  end

  def export_pdf
    pdf = ::Outsider::Voice::ReportPdf.new(board, Current.account)
    send_data pdf.render, filename: pdf.filename, type: 'application/pdf'
  end

  def export_name
    return "ligacoes-#{month}" if params[:source] == 'history'

    period = board.period
    names = { 'agents' => 'ligacoes-por-vendedor', 'days' => 'ligacoes-por-dia' }
    "#{names.fetch(params[:kind], 'ligacoes')}-#{period.from_date}-a-#{period.to_date}"
  end

  def month
    ::Outsider::Crm::MonthlyConfig.month(params[:month])
  end

  def month_range
    Date.strptime(month, '%Y-%m').in_time_zone(settings.time_zone).all_month
  end

  def filtered
    scope = ::Outsider::Voice::CallAccess.new(crm_access, settings).scope(::Outsider::Voice::Call.where(account_id: Current.account.id).external)
    scope = params[:to_return].present? ? scope.to_return : scope.where(started_at: month_range)
    scope.where(params.slice(*FILTERS).permit(*FILTERS).to_h.compact_blank)
  end

  def call_json(call)
    call.slice(:id, :direction, :status, :from_number, :to_number, :did, :state_code, :started_at, :answered_at, :ended_at,
               :talk_seconds, :returned_at, :opportunity_id, :contact_id).merge(
                 customer_number: call.customer_number, user: ::Outsider::Crm::Serializer.user(call.user),
                 contact_name: call.contact&.name, returned_by: ::Outsider::Crm::Serializer.user(call.returned_by),
                 recording_url: call.recording.attached? ? rails_blob_path(call.recording, only_path: true) : nil
               )
  end
end
