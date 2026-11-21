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
                  get :report
                  %i[substatus field status technician attendance_type].each { |action| put action }
                end
              end
              resources :customers, only: [:index]
              # cadastrar cliente no ERP pela função do Mais Prático (pré-cadastro)
              resources :clients, only: [:create] do
                collection do
                  get :options
                  get :lookup
                end
              end
              resource :contact_link, only: [:create, :destroy]
              resources :lists, only: [:index]
              resources :catalog, only: [:index] do
                get :technical, on: :collection
              end
              resources :quotes, only: [:index]
              # seção ERP: listas com todo o histórico e o detalhe (kind: quotes, orders, sales, invoices, service_invoices)
              get 'records/:kind', to: 'records#index', constraints: { kind: /quotes|orders|sales|invoices|service_invoices/ }
              get 'records/:kind/:company/:number', to: 'records#show',
                                                    constraints: { kind: /quotes|orders|sales|invoices|service_invoices/,
                                                                   company: /[a-z0-9_]+/, number: /\d+/ }
              get 'records/quotes/:company/:number/pdf', to: 'records#pdf', defaults: { kind: 'quotes' },
                                                         constraints: { company: /[a-z0-9_]+/, number: /\d+/ }
              # orçamento de peças e serviços feito no chat (separado da proposta comercial do CRM)
              resources :budgets, only: [:index, :show, :create, :update, :destroy] do
                collection do
                  post :import
                  post :revise
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
                  post :cancel_revision
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
