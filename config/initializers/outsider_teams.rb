# OUTSIDER: canal do Microsoft Teams (Entrega 26; ver app/models/outsider/teams_connection.rb). O ouvinte manda para o
# Teams o que sai nas caixas dele; as rotas são a tela de Configurações e o endereço de mensagens do robô.
Rails.application.config.to_prepare do
  AsyncDispatcher.prepend(Outsider::TeamsDispatcher) unless AsyncDispatcher < Outsider::TeamsDispatcher

  # o event_handlers.rb roda antes deste arquivo e já registrou os ouvintes sem o do Teams: registra aqui
  async = Rails.configuration.try(:dispatcher)&.async_dispatcher
  registered = async.nil? || async.send(:local_registrations).any? { |registration| registration.listener.is_a?(Outsider::TeamsListener) }
  async.subscribe(Outsider::TeamsListener.instance) unless registered
end

Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :teams_connections, only: [:index, :create, :update, :destroy] do
              member do
                post :test
                get :manifest
              end
            end
          end
        end
      end
    end
  end

  post 'outsider/teams/:token/messages', to: 'outsider/teams_webhooks#create', as: :outsider_teams_messages
end
