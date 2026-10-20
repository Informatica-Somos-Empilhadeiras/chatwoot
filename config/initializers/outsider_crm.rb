# OUTSIDER: rotas do CRM (ver app/models/outsider/crm.rb e app/controllers/api/v1/accounts/outsider/crm/)
# rubocop:disable Metrics/BlockLength
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            namespace :crm do
              resource :access, only: [:show]
              resource :settings, only: [:show, :update]
              resource :reports, only: [:show]
              resource :performance, only: [:show]
              resource :goals, only: [:show, :update]
              resource :commission, only: [:show, :update]
              resource :automations, only: [] do
                post :stalled
              end
              resources :automation_rules, only: [:index, :create, :update, :destroy]
              resource :received_forwards, only: [:show] do
                post :mark
              end
              resources :business_units, only: [:index, :show, :create, :update, :destroy] do
                resources :members, controller: 'business_unit_members', only: [:create, :update, :destroy]
              end
              resources :pipelines, only: [:index, :show, :create, :update, :destroy]
              resources :lost_reasons, only: [:index, :create, :update, :destroy]
              resources :custom_fields, only: [:index, :create, :update, :destroy]
              resources :contacts, only: [:show] do
                collection { get :summaries }
                member { get :history }
              end
              resources :opportunities, only: [:index, :show, :create, :update, :destroy] do
                collection do
                  get :board
                  get :summary
                  get :export
                end
                member { patch :move }
                resources :tasks, controller: 'opportunity_tasks', only: [:index, :create, :update, :destroy]
                resources :activities, controller: 'opportunity_activities', only: [:index, :create, :destroy]
                resources :audits, controller: 'opportunity_audits', only: [:index]
                resource :forward, controller: 'opportunity_forwards', only: [:show, :create]
              end
              resources :tasks, only: [:index]
            end
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength

# OUTSIDER: automação "negócio parado" e regras com gatilho de tempo (Outsider::Crm::StalledOpportunitiesJob), de hora em hora.
# Job.create e não load_from_hash!: o load_from_hash! apaga os jobs do config/schedule.yml que não
# estiverem no hash passado. Para tirar o agendamento: Sidekiq::Cron::Job.destroy('outsider_crm_stalled_opportunities_job').
Rails.application.reloader.to_prepare do
  if Sidekiq.server?
    Sidekiq::Cron::Job.create(name: 'outsider_crm_stalled_opportunities_job', cron: '20 * * * *',
                              class: 'Outsider::Crm::StalledOpportunitiesJob', queue: 'scheduled_jobs')
  end
end
