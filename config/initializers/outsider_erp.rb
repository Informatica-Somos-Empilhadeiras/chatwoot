# OUTSIDER: rotas da integração com o ERP Mais Prático (ver app/services/outsider/erp/settings.rb e
# app/controllers/api/v1/accounts/outsider/erp/). Mudou rota: reiniciar o Rails.
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            namespace :erp do
              resource :settings, only: [:show, :update] do
                post :test
                get :payment_terms
              end
              resource :status, only: [:show]
              resources :service_orders, only: [:index] do
                collection do
                  get :board
                  %i[substatus field status technician attendance_type].each { |action| put action }
                end
              end
              resources :customers, only: [:index]
              resource :contact_link, only: [:create, :destroy]
              resources :lists, only: [:index]
              resources :catalog, only: [:index]
              resources :quotes, only: [:index, :create]
            end
          end
        end
      end
    end
  end
end
