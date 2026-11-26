# OUTSIDER: locais do cliente (Outsider::ContactPlaces), no painel do contato da conversa e no Agendar OS. Quem vê o
# contato vê e cadastra os locais dele.
#   GET    outsider/contacts/:contact_id/places
#   POST   outsider/contacts/:contact_id/places        { place: { name, address, latitude, longitude, main } }
#   PATCH  outsider/contacts/:contact_id/places/:id    { place: { name, address, main } }
#   DELETE outsider/contacts/:contact_id/places/:id
class Api::V1::Accounts::Outsider::ContactPlacesController < Api::V1::Accounts::BaseController
  before_action :fetch_contact

  rescue_from(::Outsider::ContactPlaces::Invalid) { |error| render json: { error: error.message }, status: :unprocessable_entity }
  rescue_from(ActiveRecord::RecordInvalid) { |error| render json: { error: 'invalid', message: error.message }, status: :unprocessable_entity }

  def index
    render json: { payload: places.all.map(&:as_place_json) }
  end

  def create
    render json: places.create(place_params.permit(:name, :address, :latitude, :longitude, :main)).as_place_json, status: :created
  end

  def update
    render json: places.update(places.find(params[:id]), place_params.permit(:name, :address, :main)).as_place_json
  end

  def destroy
    places.destroy(places.find(params[:id]))
    head :no_content
  end

  private

  def fetch_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def places
    @places ||= ::Outsider::ContactPlaces.new(@contact, Current.user)
  end

  def place_params
    params.require(:place)
  end
end
