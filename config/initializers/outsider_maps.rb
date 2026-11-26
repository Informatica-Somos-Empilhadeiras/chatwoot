# OUTSIDER: Google Maps na agenda: chave do Maps (navegador) e locais do cliente
# (ver app/controllers/api/v1/accounts/outsider/maps_controller.rb e contact_places_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resource :maps, only: [:show, :update], controller: 'maps'
            namespace :erp do
              get :schedule_map, to: 'schedule_map#show'
              get 'schedule_map/client', to: 'schedule_map#client'
              post 'schedule_map/complete', to: 'schedule_map#complete'
            end
            resources :contacts, only: [] do
              resources :places, only: [:index, :create, :update, :destroy], controller: 'contact_places'
            end
          end
        end
      end
    end
  end
end
