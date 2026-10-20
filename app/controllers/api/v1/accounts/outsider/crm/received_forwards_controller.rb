# OUTSIDER: aviso de negócio recebido por encaminhamento (Outsider::Crm::ReceivedForwards).
# show lista o que a pessoa ainda não abriu; mark registra que fechou o aviso ou abriu o negócio.
class Api::V1::Accounts::Outsider::Crm::ReceivedForwardsController < Api::V1::Accounts::Outsider::Crm::BaseController
  def show
    render json: { payload: received.items }
  end

  def mark
    received.mark(Array(params[:opportunity_ids]), opened: ActiveModel::Type::Boolean.new.cast(params[:opened]) || false)
    render json: { payload: received.items }
  end

  private

  def received
    @received ||= ::Outsider::Crm::ReceivedForwards.new(crm_access, Current.user)
  end
end
