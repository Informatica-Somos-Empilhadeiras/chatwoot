# OUTSIDER: pipelines e suas etapas. Todos da unidade veem; administradores e gestores da
# unidade criam e alteram. As etapas vão juntas em stages_attributes (com _destroy para remover).
class Api::V1::Accounts::Outsider::Crm::PipelinesController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :ensure_unit_manager, only: [:update, :destroy]

  def index
    pipelines = crm_scope(::Outsider::Crm::Pipeline).where(business_unit_id: crm_access.visible_unit_ids)
    pipelines = pipelines.where(business_unit_id: params[:business_unit_id]) if params[:business_unit_id].present?
    render json: pipelines.ordered.includes(:stages).map { |pipeline| ::Outsider::Crm::Serializer.pipeline(pipeline) }
  end

  def show
    render json: ::Outsider::Crm::Serializer.pipeline(@pipeline)
  end

  def create
    unit = crm_scope(::Outsider::Crm::BusinessUnit).find(pipeline_params[:business_unit_id])
    return render_forbidden unless crm_access.manage_unit?(unit.id)

    pipeline = crm_scope(::Outsider::Crm::Pipeline).create!(pipeline_params)
    render json: ::Outsider::Crm::Serializer.pipeline(pipeline.reload), status: :created
  end

  def update
    @pipeline.update!(pipeline_params.except(:business_unit_id))
    render json: ::Outsider::Crm::Serializer.pipeline(@pipeline.reload)
  end

  # Pipeline com oportunidades não é apagado: desative (active: false)
  def destroy
    if @pipeline.destroy
      head :no_content
    else
      render json: { error: 'in_use', message: @pipeline.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def fetch_pipeline
    @pipeline = crm_scope(::Outsider::Crm::Pipeline).where(business_unit_id: crm_access.visible_unit_ids).find(params[:id])
  end

  def ensure_unit_manager
    render_forbidden unless crm_access.manage_unit?(@pipeline.business_unit_id)
  end

  def pipeline_params
    params.require(:pipeline).permit(
      :business_unit_id, :name, :active, :position,
      stages_attributes: [:id, :name, :position, :probability, :kind, :color, :sla_hours, :_destroy]
    )
  end
end
