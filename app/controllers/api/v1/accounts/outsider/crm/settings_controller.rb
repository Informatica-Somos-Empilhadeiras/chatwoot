# OUTSIDER: configurações do CRM da conta (só administradores alteram).
class Api::V1::Accounts::Outsider::Crm::SettingsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin, only: [:update]

  def show
    render json: settings.to_h
  end

  def update
    render json: settings.update(params.require(:settings).permit(*::Outsider::Crm::Settings.permitted))
  rescue ::Outsider::Crm::Settings::Invalid => e
    render json: { error: 'invalid', fields: e.message.split(', ') }, status: :unprocessable_entity
  end

  private

  def settings
    @settings ||= ::Outsider::Crm::Settings.new(Current.account)
  end
end
