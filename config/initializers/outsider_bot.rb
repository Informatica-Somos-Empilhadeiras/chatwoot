# OUTSIDER: automação por bot desenhada como fluxograma (ver app/services/outsider/bot/runner.rb e
# app/controllers/api/v1/accounts/outsider/bot_flows_controller.rb)
Rails.application.config.to_prepare do
  AsyncDispatcher.prepend(Outsider::BotDispatcher) unless AsyncDispatcher < Outsider::BotDispatcher

  # o event_handlers.rb roda antes deste arquivo e já registrou os ouvintes sem o do bot: registra aqui
  async = Rails.configuration.try(:dispatcher)&.async_dispatcher
  registered = async.nil? || async.send(:local_registrations).any? { |registration| registration.listener.is_a?(Outsider::BotListener) }
  async.subscribe(Outsider::BotListener.instance) unless registered
end

Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :bot_flows, only: [:index, :show, :create, :update, :destroy] do
              post :duplicate, on: :member
              post :run_block, on: :collection
            end
            resources :bot_connections, only: [:index, :create, :update, :destroy] do
              post :test, on: :member
              get :folders, on: :member
            end
            resources :bot_datasets, only: [:index, :show, :create, :update, :destroy] do
              member do
                post :rows
                post :finish
                get :lookup
              end
            end
            resources :bot_logs, only: [:index]
          end
        end
      end
    end
  end
end

# OUTSIDER: limpeza diária do registro de chamadas do bot (7 dias). Job criado um a um (create), nunca com
# load_from_hash!, que apaga os agendamentos do schedule.yml que não estiverem no hash.
Rails.application.reloader.to_prepare do
  if Sidekiq.server?
    Sidekiq::Cron::Job.create(name: 'outsider_bot_log_cleanup_job', cron: '50 3 * * *',
                              class: 'Outsider::Bot::LogCleanupJob', queue: 'scheduled_jobs')
  end
end
