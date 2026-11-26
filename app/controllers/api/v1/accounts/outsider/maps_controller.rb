# OUTSIDER: chave do Google Maps (Outsider::MapsSettings). Todos da conta leem (o navegador precisa dela para o Street
# View e o mapa); só o administrador troca.
#   GET outsider/maps   { key, map_id, can_manage }
#   PUT outsider/maps   { key, map_id }
class Api::V1::Accounts::Outsider::MapsController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator, only: [:update]

  rescue_from(::Outsider::MapsSettings::Invalid) { |error| render json: { error: error.message }, status: :unprocessable_entity }

  def show
    render json: { key: settings.key, map_id: settings.map_id, can_manage: Current.account_user.administrator? }
  end

  def update
    key = settings.update(params[:key], map_id: params.key?(:map_id) ? params[:map_id].to_s : nil)
    render json: { key: key, map_id: settings.map_id, can_manage: true }
  end

  private

  def settings
    ::Outsider::MapsSettings.new(Current.account)
  end

  def ensure_administrator
    head :forbidden unless Current.account_user.administrator?
  end
end
