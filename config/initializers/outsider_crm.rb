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
              resources :agent_accesses, only: [:index, :update]
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
                  get :unowned
                end
                member do
                  patch :move
                  post :claim
                end
                resources :tasks, controller: 'opportunity_tasks', only: [:index, :create, :update, :destroy]
                resources :activities, controller: 'opportunity_activities', only: [:index, :create, :destroy]
                resources :audits, controller: 'opportunity_audits', only: [:index]
                resource :forward, controller: 'opportunity_forwards', only: [:show, :create]
              end
              resources :tasks, only: [:index]
              # propostas (Outsider::Crm::Proposal), catálogo e modelos
              resources :products, only: [:index, :show, :create, :update, :destroy] do
                member do
                  put :image, action: :upload_image
                  delete :image, action: :remove_image
                end
              end
              resources :proposal_templates, only: [:index, :show, :create, :update, :destroy] do
                member do
                  put 'images/:slot', action: :upload_image
                  delete 'images/:slot', action: :remove_image
                  post :preview
                  post :layout_images, action: :upload_layout_image
                end
                get 'default_images/:slot', action: :default_image, on: :collection
              end
              resource :proposal_settings, only: [:show] do
                patch :general
                patch :company
                patch 'access/:user_id', action: :access
                patch 'signatures/:user_id', action: :signature
              end
              resource :proposal_signature, only: [:show, :update]
              resource :proposal_reports, only: [:show]
              resources :proposals, only: [:index, :show, :create, :update, :destroy] do
                collection { get :prefill }
                member do
                  get :pdf
                  patch :status
                end
                resources :sends, only: [:new, :create], controller: 'proposal_sends'
              end
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

# OUTSIDER: liga e desliga o CRM (Outsider::Crm::Switch) sem editar arquivos do Chatwoot: campo virtual no
# Account, coluna "CRM" no dashboard de contas do Super Admin e limpeza da chave por agente quando a pessoa sai
# da conta ou muda de papel. on_load (e não to_prepare) porque carregar o AccountDashboard na subida do Rails
# consulta Redis e banco (ChatwootApp.chatwoot_cloud?) e quebraria o assets:precompile do build.
Rails.autoloaders.main.on_load('Account') do |klass, _path|
  klass.include(Outsider::Crm::AccountSwitch) unless klass < Outsider::Crm::AccountSwitch
end
Rails.autoloaders.main.on_load('AccountUser') do |klass, _path|
  klass.include(Outsider::Crm::AccountUserSwitch) unless klass < Outsider::Crm::AccountUserSwitch
end
Rails.autoloaders.main.on_load('AccountDashboard') do |klass, _path|
  klass.prepend(Outsider::Crm::AccountDashboardSwitch) unless klass < Outsider::Crm::AccountDashboardSwitch
end
