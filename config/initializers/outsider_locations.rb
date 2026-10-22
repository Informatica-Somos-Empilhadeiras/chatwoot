# OUTSIDER: enviar localização pelo WhatsApp (ver app/controllers/api/v1/accounts/outsider/locations_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :locations, only: [:create] do
              collection do
                get :search
                get :saved
                post :saved, action: :save
                delete 'saved/:id', action: :remove
              end
            end
          end
        end
      end
    end
  end
end
