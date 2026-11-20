# OUTSIDER: rotas da integração com o ERP Mais Prático (ver app/services/outsider/erp/settings.rb e
# app/controllers/api/v1/accounts/outsider/erp/). Mudou rota: reiniciar o Rails.
# rubocop:disable Metrics/BlockLength
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
                  get :list
                  %i[substatus field status technician attendance_type].each { |action| put action }
                end
              end
              resources :customers, only: [:index]
              resource :contact_link, only: [:create, :destroy]
              resources :lists, only: [:index]
              resources :catalog, only: [:index] do
                get :technical, on: :collection
              end
              resources :quotes, only: [:index] do
                get :list, on: :collection
              end
              resources :sales_orders, only: [:index]
              # orçamento de peças e serviços feito no chat (separado da proposta comercial do CRM)
              resources :budgets, only: [:index, :show, :create, :update, :destroy] do
                collection do
                  post :import
                  get :options
                end
                member do
                  post :submit
                  get :pdf
                  post :copy
                  get :delivery
                  get :contacts
                  post :deliver
                  post :approve_discount
                end
              end
            end
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
