# OUTSIDER: perfis de acesso por tela (ver app/services/outsider/access.rb). Rotas da tela Configurações > Perfis de
# acesso e do acesso da pessoa logada; a API recusa o que o perfil não deixa (prepend no BaseController da API das
# contas, sem mexer nos controladores do Chatwoot); campo "Telas só para administradores" no Super Admin.
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resource :access, only: [:show], controller: 'access'
            resources :access_profiles, only: [:index, :create, :update, :destroy]
            resources :access_people, only: [:index, :create, :update]
          end
        end
      end
    end
  end
end

Rails.application.config.to_prepare do
  base = Api::V1::Accounts::BaseController
  base.prepend(Outsider::Access::ApiGuard) unless base < Outsider::Access::ApiGuard
end

# on_load (e não to_prepare): carregar o AccountDashboard na subida do Rails consulta Redis e banco e quebra o
# assets:precompile (ver config/initializers/outsider_crm.rb)
Rails.autoloaders.main.on_load('Account') do |klass, _path|
  klass.include(Outsider::Access::AccountCeiling) unless klass < Outsider::Access::AccountCeiling
end
Rails.autoloaders.main.on_load('AccountDashboard') do |klass, _path|
  klass.prepend(Outsider::Access::AccountDashboardField) unless klass < Outsider::Access::AccountDashboardField
end
