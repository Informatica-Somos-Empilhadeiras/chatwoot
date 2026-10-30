# OUTSIDER: pedidos de transferência de conversa entre agentes (ver app/services/outsider/conversation_transfer.rb).
class Api::V1::Accounts::Outsider::TransferRequestsController < Api::V1::Accounts::BaseController
  before_action :find_request, except: [:index, :create]

  rescue_from ::Outsider::ConversationTransfer::Error do |error|
    status = error.code == :not_found ? :not_found : :unprocessable_entity
    render json: { error: error.code }, status: status
  end

  def index
    overview = transfers.overview
    render json: overview.transform_values { |list| list.map { |transfer| serialize(transfer) } }
  end

  def create
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    render json: serialize(transfers.request(conversation, params[:note]))
  end

  def accept
    render json: serialize(transfers.accept(@transfer))
  end

  def decline
    render json: serialize(transfers.decline(@transfer, params[:note]))
  end

  def acknowledge
    render json: serialize(transfers.acknowledge(@transfer))
  end

  def destroy
    render json: serialize(transfers.cancel(@transfer))
  end

  private

  def transfers
    @transfers ||= ::Outsider::ConversationTransfer.new(Current.account, Current.user)
  end

  def find_request
    @transfer = transfers.requests.find(params[:id])
  end

  def serialize(transfer)
    ::Outsider::ConversationTransfer.serialize(transfer)
  end
end
