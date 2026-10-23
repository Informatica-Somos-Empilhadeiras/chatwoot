# OUTSIDER: enviar localização pelo WhatsApp (caixas da Evolution). Busca de endereço, endereços
# salvos da conta (só o administrador salva e apaga) e o envio, que pode fazer quem responde na
# conversa (ver app/services/outsider/location_sender.rb).
class Api::V1::Accounts::Outsider::LocationsController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator, only: [:save, :remove]

  rescue_from ::Outsider::EvolutionApi::Error do |error|
    render json: { error: error.code, message: error.message }, status: :unprocessable_entity
  end

  rescue_from ::Outsider::LocationSender::Invalid, ::Outsider::SavedLocations::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  rescue_from ::Outsider::Geocoder::Error do
    render json: { error: 'geocoder_unavailable' }, status: :service_unavailable
  end

  def search
    render json: { payload: ::Outsider::Geocoder.new.search(params[:q]) }
  end

  def saved
    render json: { payload: saved_locations.all, can_manage: Current.account_user.administrator? }
  end

  def save
    render json: saved_locations.create(params.require(:location).permit(:name, :address, :latitude, :longitude))
  end

  def remove
    saved_locations.destroy(params.require(:id))
    head :no_content
  end

  def create
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    authorize conversation, :show?

    location = params.require(:location).permit(:name, :address, :latitude, :longitude)
    message = ::Outsider::LocationSender.new(conversation: conversation, user: Current.user, location: location).perform
    # a mensagem vai junto para a tela mostrar na hora, sem esperar o aviso em tempo real
    render json: { message_id: message&.id, message: message&.push_event_data }
  end

  private

  def saved_locations
    ::Outsider::SavedLocations.new(Current.account)
  end

  def ensure_administrator
    head :forbidden unless Current.account_user.administrator?
  end
end
