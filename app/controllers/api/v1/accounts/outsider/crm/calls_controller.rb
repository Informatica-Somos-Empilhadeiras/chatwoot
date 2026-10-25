# OUTSIDER: ligações da Telefonia (Entrega 22): lista com filtros, a fila de retorno e o painel
# (Outsider::Voice::Wallboard, Entrega 23). Cada pessoa vê o que Outsider::Voice::CallAccess deixa.
class Api::V1::Accounts::Outsider::Crm::CallsController < Api::V1::Accounts::Outsider::Crm::BaseController
  PER_PAGE = 50
  FILTERS = %w[direction status user_id].freeze

  def index
    calls = filtered.includes(:user, :contact, :returned_by).order(started_at: :desc)
    page = [params[:page].to_i, 1].max
    render json: { payload: calls.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map { |call| call_json(call) },
                   meta: { page: page, per_page: PER_PAGE, total: calls.count } }
  end

  # painel da Telefonia (Entrega 23)
  def wallboard
    render json: ::Outsider::Voice::Wallboard.new(crm_access, period: params[:period], user_id: params[:user_id], zone: params[:zone]).to_h
  end

  private

  def month
    ::Outsider::Crm::MonthlyConfig.month(params[:month])
  end

  def filtered
    scope = ::Outsider::Voice::CallAccess.new(crm_access, ::Outsider::Voice::Settings.new(Current.account))
                                         .scope(::Outsider::Voice::Call.where(account_id: Current.account.id).external)
    scope = params[:to_return].present? ? scope.to_return : scope.where(started_at: ::Outsider::Crm::MonthlyConfig.range(month))
    scope.where(params.slice(*FILTERS).permit(*FILTERS).to_h.compact_blank)
  end

  def call_json(call)
    call.slice(:id, :direction, :status, :from_number, :to_number, :did, :state_code, :started_at, :answered_at, :ended_at,
               :talk_seconds, :returned_at, :opportunity_id, :contact_id).merge(
                 customer_number: call.customer_number, user: ::Outsider::Crm::Serializer.user(call.user),
                 contact_name: call.contact&.name, returned_by: ::Outsider::Crm::Serializer.user(call.returned_by)
               )
  end
end
