# OUTSIDER: motivos de perda e de encaminhamento. Todos do CRM leem; administradores alteram.
class Api::V1::Accounts::Outsider::Crm::LostReasonsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin, except: [:index]
  before_action :fetch_reason, only: [:update, :destroy]

  def index
    render json: crm_scope(::Outsider::Crm::LostReason).ordered.map { |reason| ::Outsider::Crm::Serializer.lost_reason(reason) }
  end

  def create
    reason = crm_scope(::Outsider::Crm::LostReason).create!(reason_params)
    render json: ::Outsider::Crm::Serializer.lost_reason(reason), status: :created
  end

  def update
    @reason.update!(reason_params)
    render json: ::Outsider::Crm::Serializer.lost_reason(@reason)
  end

  # Motivo já usado não é apagado, para não perder o histórico: desative (active: false)
  def destroy
    if ::Outsider::Crm::Opportunity.exists?(lost_reason_id: @reason.id) || ::Outsider::Crm::Forward.exists?(reason_id: @reason.id)
      render json: { error: 'in_use' }, status: :unprocessable_entity
    else
      @reason.destroy!
      head :no_content
    end
  end

  private

  def fetch_reason
    @reason = crm_scope(::Outsider::Crm::LostReason).find(params[:id])
  end

  def reason_params
    params.require(:lost_reason).permit(:name, :kind, :active, :position)
  end
end
