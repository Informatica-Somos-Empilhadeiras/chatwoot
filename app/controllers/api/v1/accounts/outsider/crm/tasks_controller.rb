# OUTSIDER: lista geral de tarefas (aba Tarefas do CRM e lembretes). Por padrão as do próprio
# usuário; dá para ver as de outro responsável ou de todos, sempre só nas unidades visíveis.
class Api::V1::Accounts::Outsider::Crm::TasksController < Api::V1::Accounts::Outsider::Crm::BaseController
  LIMIT = 200
  DONE_DAYS = 30

  def index
    scope = filtered
    tasks = params[:status] == 'done' ? done(scope) : pending(scope)
    tasks = tasks.includes(:assignee, :created_by, :completed_by, opportunity: :contact).limit(LIMIT)
    render json: {
      payload: tasks.map { |task| ::Outsider::Crm::Serializer.task_with_opportunity(task, access: crm_access) },
      meta: counts(scope)
    }
  end

  private

  def filtered
    opportunities = crm_access.opportunities(crm_scope(::Outsider::Crm::Opportunity))
    opportunities = opportunities.where(business_unit_id: params[:business_unit_id]) if params[:business_unit_id].present?
    scope = crm_scope(::Outsider::Crm::Task).where(opportunity_id: opportunities.select(:id))
    case params[:assignee_id].presence || 'me'
    when 'me' then scope.where(assignee_id: Current.user.id)
    when 'all' then scope
    else scope.where(assignee_id: params[:assignee_id].to_i)
    end
  end

  def pending(scope)
    scope = scope.pending.order(Arel.sql('due_at ASC NULLS LAST'), :id)
    due_before = parse_time(params[:due_before])
    due_before ? scope.where(due_at: ..due_before) : scope
  end

  def done(scope)
    scope.where(completed_at: DONE_DAYS.days.ago..).order(completed_at: :desc)
  end

  def counts(scope)
    pending = scope.pending
    { pending: pending.count, overdue: pending.where(due_at: ...Time.current).count }
  end

  def parse_time(value)
    Time.zone.parse(value) if value.present?
  rescue ArgumentError
    nil
  end
end
