# OUTSIDER: encaminhar mensagem (ver app/controllers/api/v1/accounts/outsider/message_forwards_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :message_forwards, only: [:create]
          end
        end
      end
    end
  end
end
