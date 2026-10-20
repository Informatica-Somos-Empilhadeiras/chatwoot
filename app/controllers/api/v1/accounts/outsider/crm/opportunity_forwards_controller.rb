# OUTSIDER: encaminhamento de uma oportunidade para outra unidade. show traz as opções da tela de
# confirmação; create encaminha (Outsider::Crm::OpportunityForwarder). Só quem edita o negócio, e só
# enquanto ele está aberto.
class Api::V1::Accounts::Outsider::Crm::OpportunityForwardsController < Api::V1::Accounts::Outsider::Crm::OpportunityChildController
  before_action :ensure_can_forward

  def show
    render json: ::Outsider::Crm::ForwardOptions.new(@opportunity, access: crm_access, user: Current.user).to_h
  end

  def create
    forwarder = ::Outsider::Crm::OpportunityForwarder.new(@opportunity, access: crm_access, user: Current.user, params: forward_params)
    forward = forwarder.perform
    render json: {
      attempt_number: forward.attempt_number,
      origin: serialize(@opportunity.reload),
      opportunity: serialize(forwarder.target.reload)
    }, status: :created
  rescue ::Outsider::Crm::OpportunityForwarder::Refused => e
    render json: { error: e.code, message: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_can_forward
    return if crm_access.forward_opportunity?(@opportunity)
    return render_forbidden if @opportunity.open?

    render json: { error: 'not_open', message: I18n.t('outsider_crm.forward.errors.not_open') }, status: :unprocessable_entity
  end

  def forward_params
    params.require(:forward).permit(
      :to_business_unit_id, :pipeline_id, :owner_id, :reason_id, :notes, :complete_tasks, :create_task, :assign_conversation
    )
  end

  def serialize(opportunity)
    ::Outsider::Crm::Serializer.opportunity(opportunity, access: crm_access)
  end
end
