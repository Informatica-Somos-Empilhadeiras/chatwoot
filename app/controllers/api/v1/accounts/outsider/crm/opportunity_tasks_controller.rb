# OUTSIDER: tarefas de uma oportunidade. Quem edita o negócio cria, edita e apaga; o responsável
# pela tarefa pode concluir e adiar a sua. Vendedor só atribui tarefa a si mesmo; gestor e
# administrador escolhem qualquer membro da unidade.
class Api::V1::Accounts::Outsider::Crm::OpportunityTasksController < Api::V1::Accounts::Outsider::Crm::OpportunityChildController
  before_action :fetch_task, only: [:update, :destroy]
  before_action :ensure_can_edit_opportunity, only: [:create, :destroy]

  def index
    tasks = @opportunity.tasks.includes(:assignee, :created_by, :completed_by)
                        .order(Arel.sql('completed_at IS NOT NULL'), Arel.sql('due_at ASC NULLS LAST'), completed_at: :desc, id: :asc)
    render json: tasks.map { |task| serialize(task) }
  end

  def create
    return render_forbidden unless assignee_allowed?

    task = @opportunity.tasks.create!(
      task_params.merge(account: Current.account, created_by: Current.user, assignee_id: task_params[:assignee_id].presence || Current.user.id)
    )
    render json: serialize(task), status: :created
  end

  def update
    return render_forbidden unless crm_access.complete_task?(@task)

    attributes = crm_access.edit_opportunity?(@opportunity) ? task_params : task_params.slice(:due_at)
    return render_forbidden if attributes.key?(:assignee_id) && !assignee_allowed?(@task.assignee_id)

    @task.update!(attributes.merge(completion_attributes))
    render json: serialize(@task.reload)
  end

  def destroy
    @task.destroy!
    head :no_content
  end

  private

  def fetch_task
    @task = @opportunity.tasks.find(params[:id])
  end

  def task_params
    @task_params ||= params.require(:task).permit(:title, :description, :kind, :due_at, :assignee_id)
  end

  # completed: true conclui (guarda quem e quando); false reabre
  def completion_attributes
    return {} unless params[:task].key?(:completed)

    done = ActiveModel::Type::Boolean.new.cast(params[:task][:completed])
    return {} if done == @task.completed?

    { completed_at: done ? Time.current : nil, completed_by: done ? Current.user : nil }
  end

  def assignee_allowed?(current_assignee_id = nil)
    assignee_id = task_params[:assignee_id]
    return true if assignee_id.blank? || [current_assignee_id, Current.user.id].include?(assignee_id.to_i)

    crm_access.manage_unit?(@opportunity.business_unit_id) &&
      crm_access.assignable_user_ids(@opportunity.business_unit_id).include?(assignee_id.to_i)
  end

  def serialize(task)
    ::Outsider::Crm::Serializer.task(task, access: crm_access)
  end
end
