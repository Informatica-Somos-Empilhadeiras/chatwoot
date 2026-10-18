# OUTSIDER: busca de conversas (ver app/controllers/api/v1/accounts/outsider/conversation_searches_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :conversation_searches, only: [:index]
          end
        end
      end
    end
  end
end
