# OUTSIDER: aparência da conta (favicon, título, logo e papel de parede; ver app/services/outsider/branding.rb).
# on_load (e não to_prepare), como no outsider_crm.rb, para não carregar o Account na subida do Rails.
Rails.autoloaders.main.on_load('Account') do |klass, _path|
  klass.include(Outsider::AccountBranding) unless klass < Outsider::AccountBranding
end

Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resource :branding, only: [:show, :update]
          end
        end
      end
    end
  end
end
