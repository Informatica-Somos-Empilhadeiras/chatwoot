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
