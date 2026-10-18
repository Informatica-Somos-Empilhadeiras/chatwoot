# OUTSIDER: busca dentro da conversa e ida até uma data
# (ver app/controllers/api/v1/accounts/outsider/conversation_histories_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :conversations, only: [] do
              resource :history, only: [], controller: 'conversation_histories' do
                get :search
                get :days
                get :locate
              end
            end
          end
        end
      end
    end
  end
end
