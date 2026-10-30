# OUTSIDER: busca de conversas, contatos e mensagens e pedidos de transferência de conversa
# (ver app/controllers/api/v1/accounts/outsider/conversation_searches_controller.rb,
# message_searches_controller.rb e transfer_requests_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :conversation_searches, only: [:index]
            resources :message_searches, only: [:index]
            resources :transfer_requests, only: [:index, :create, :destroy] do
              member do
                post :accept
                post :decline
                post :acknowledge
              end
            end
          end
        end
      end
    end
  end
end
