# OUTSIDER: canal do Microsoft Teams (Entrega 26; ver app/models/outsider/teams_connection.rb). O ouvinte manda para o
# Teams o que sai nas caixas dele; as rotas são a tela de Configurações e o endereço de mensagens do robô.
# Também o "Conectar meu Teams" (app/models/outsider/teams_link.rb): rotas da tela, da área Teams e dos avisos da Microsoft.
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
            # "Conectar meu Teams" (login com a conta Microsoft de cada pessoa)
            get 'teams_graph', to: 'teams_graph#show'
            put 'teams_graph/app', to: 'teams_graph#save_app'
            post 'teams_graph/consent', to: 'teams_graph#consent'
            post 'teams_graph/authorize', to: 'teams_graph#authorize'
            post 'teams_graph/finish', to: 'teams_graph#finish'
            get 'teams_graph/teams', to: 'teams_graph#directory'
            patch 'teams_graph/me', to: 'teams_graph#update_me'
            delete 'teams_graph/me', to: 'teams_graph#disconnect'
            delete 'teams_graph/links/:link_id', to: 'teams_graph#destroy_link'
            resources :teams_threads, only: [:index, :show] do
              collection { get :summary }
              member do
                get :messages
                post :messages, action: :send_message
                post 'messages/:message_id/retry', action: :retry
                post 'messages/:message_id/attachments/:index/preview', action: :preview
                get :members
                post :read
              end
            end
          end
        end
      end
    end
  end

  post 'outsider/teams/:token/messages', to: 'outsider/teams_webhooks#create', as: :outsider_teams_messages
  post 'outsider/teams/graph/notifications', to: 'outsider/teams_graph_webhooks#notifications'
  post 'outsider/teams/graph/lifecycle', to: 'outsider/teams_graph_webhooks#lifecycle'
  get 'outsider/teams/oauth/callback', to: 'outsider/teams_graph_webhooks#callback'
  get 'outsider/teams/media', to: 'outsider/teams_media#show'
end

# OUTSIDER: "Conectar meu Teams": de hora em hora renova os avisos da Microsoft (valem até 3 dias). Job criado um a um
# (create), nunca com load_from_hash!, que apagaria os agendamentos do schedule.yml.
Rails.application.reloader.to_prepare do
  if Sidekiq.server?
    Sidekiq::Cron::Job.create(name: 'outsider_teams_graph_renew_job', cron: '17 * * * *',
                              class: 'Outsider::Teams::Graph::RenewJob', queue: 'scheduled_jobs')
  end
end
