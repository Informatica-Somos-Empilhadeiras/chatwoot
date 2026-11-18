# OUTSIDER: a API recusa o que o perfil de acesso não deixa (ver Outsider::Access). Entra antes de cada ação da API das
# contas (prepend em Api::V1::Accounts::BaseController, config/initializers/outsider_access.rb), sem mexer nos
# controladores do Chatwoot: Não vê recusa tudo da tela; Vê recusa o que grava. Administrador passa sempre.
# OUTSIDER_ACCESS=off no .env desliga a checagem (o menu continua seguindo os perfis).
module Outsider::Access::ApiGuard
  def self.prepended(base)
    base.before_action :outsider_access_guard
  end

  private

  def outsider_access_guard
    return if ENV.fetch('OUTSIDER_ACCESS', 'on').to_s.downcase == 'off'
    return unless Current.account_user && !Current.account_user.administrator?

    screen = Outsider::Access::Catalog.screen_for_controller(controller_path)
    return unless screen

    level = Outsider::Access.for(Current.account_user).level(screen)
    return if level == 'none' ? false : (level != 'view' || outsider_access_read?)

    render json: { error: I18n.t('outsider_access.refused'), outsider_access: screen, level: level }, status: :forbidden
  end

  def outsider_access_read?
    request.get? || request.head? || Outsider::Access::Catalog::VIEW_SAFE_ACTIONS.include?(action_name)
  end
end
