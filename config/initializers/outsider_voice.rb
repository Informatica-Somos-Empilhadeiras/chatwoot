# OUTSIDER: telefonia (Entrega 22). Rotas do telefone no navegador, das telas do CRM e da central (Asterisk),
# que entra só com o token OUTSIDER_VOICE_TOKEN (ver app/controllers/outsider/voice_central_controller.rb).
# rubocop:disable Metrics/BlockLength
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resource :voice, only: [], controller: 'voice' do
              get :me
              get :lookup
              get :team
              post :recording
            end
            namespace :crm do
              resource :voice_settings, only: [:show, :update]
              resource :call_goals, only: [:show, :update]
              resources :calls, only: [:index] do
                collection do
                  get :wallboard
                  get :export
                end
                delete :recording, on: :member, action: :destroy_recording
              end
              resources :call_recordings, only: [:index] do
                member do
                  get :forward, action: :forward_options
                  post :forward
                end
              end
            end
          end
        end
      end
    end
  end

  scope 'outsider/voice/central/:account_id', controller: 'outsider/voice_central', as: 'outsider_voice_central' do
    get :pjsip
    get :extensions
    post :inbound
    post :outbound
    post :internal
    post :answered
    post :hangup
    post :status
  end
end
# rubocop:enable Metrics/BlockLength

# OUTSIDER: gravações de ligação vencidas (Entrega 25), uma vez por dia de madrugada. Job criado um a um (create),
# nunca com load_from_hash!, que apaga os agendamentos do schedule.yml que não estiverem no hash.
Rails.application.reloader.to_prepare do
  if Sidekiq.server?
    Sidekiq::Cron::Job.create(name: 'outsider_voice_recording_cleanup_job', cron: '40 4 * * *',
                              class: 'Outsider::Voice::RecordingCleanupJob', queue: 'scheduled_jobs')
  end
end
