# OUTSIDER: Configurações > Telefonia (Entrega 22). Dados da operadora, números por estado, ramais e regras
# de toque (Outsider::Voice::Settings), o estado da central e o que falta para instalar. Só administradores.
class Api::V1::Accounts::Outsider::Crm::VoiceSettingsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin

  rescue_from ::Outsider::Voice::Settings::Invalid do |error|
    render json: { error: 'invalid', fields: error.errors }, status: :unprocessable_entity
  end

  def show
    render json: payload
  end

  # os telefones abertos na conta buscam o ramal de novo (ver voice/CallCard.vue)
  def update
    settings.update(params.require(:settings).to_unsafe_h)
    ::Outsider::Crm::LiveUpdates.broadcast(Current.account.id, 'voice')
    render json: payload
  end

  private

  def settings
    @settings ||= ::Outsider::Voice::Settings.new(Current.account)
  end

  def payload
    {
      settings: settings.as_json, status: ::Outsider::Voice::CentralStatus.new(Current.account).to_h,
      install: { account_id: Current.account.id,
                 token_set: ENV.fetch('OUTSIDER_VOICE_TOKEN', '').length >= ::Outsider::VoiceCentralController::MIN_TOKEN },
      people: Current.account.users.order(:name).map { |user| { id: user.id, name: user.name, thumbnail: user.avatar_url } }
    }
  end
end
