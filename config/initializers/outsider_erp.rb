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
                  # envio do relatório ao cliente (WhatsApp/e-mail), como o do orçamento
                  get :delivery
                  get :contacts
                  post :deliver
                  %i[substatus field status technician attendance_type].each { |action| put action }
                end
              end
              resources :customers, only: [:index]
              # Modelos de relatório: estúdio dos modelos de impressão da OS e do orçamento (só administradores)
              resources :print_templates, only: [:index, :show, :create, :update, :destroy] do
                collection do
                  get :sample
                  get :photo
                  put :bindings, action: :bindings_update
                end
                member do
                  post :restore
                  post :preview
                  post :upload_image
                end
              end
              # cadastrar cliente no ERP pela função do Mais Prático (pré-cadastro)
              resources :clients, only: [:create] do
                collection do
                  get :options
                  get :lookup
                  get :company
                end
              end
              resource :contact_link, only: [:create, :destroy]
              resources :lists, only: [:index]
              resources :catalog, only: [:index, :show] do
                get :technical, on: :collection
                get :photo_counts, action: :photo_counts_for, on: :collection
                # aba Produtos e orçamento: as fotos do produto (no Nextcloud) e o envio de uma ao cliente
                member do
                  get :photos
                  get :thumbnail
                  get 'photos/:photo_id', action: :photo, constraints: { photo_id: /\d+/ }
                  post 'photos/:photo_id/send', action: :send_photo, constraints: { photo_id: /\d+/ }
                end
              end
              resources :quotes, only: [:index]
              # seção ERP: listas com todo o histórico e o detalhe (kind: quotes, orders, sales, invoices, service_invoices)
              get 'records/:kind', to: 'records#index', constraints: { kind: /quotes|orders|sales|invoices|service_invoices/ }
              get 'records/:kind/:company/:number', to: 'records#show',
                                                    constraints: { kind: /quotes|orders|sales|invoices|service_invoices/,
                                                                   company: /[a-z0-9_]+/, number: /\d+/ }
              get 'records/quotes/:company/:number/pdf', to: 'records#pdf', defaults: { kind: 'quotes' },
                                                         constraints: { company: /[a-z0-9_]+/, number: /\d+/ }
              # NF-e e NFS-e: o PDF da nota espelhado do Nextcloud e o envio dele ao cliente
              get 'records/invoice_contacts', to: 'records#contacts', defaults: { kind: 'invoices' }
              get 'records/:kind/:company/:number/delivery', to: 'records#delivery',
                                                             constraints: { kind: /invoices|service_invoices/, company: /[a-z0-9_]+/,
                                                                            number: /\d+/ }
              post 'records/:kind/:company/:number/deliver', to: 'records#deliver',
                                                             constraints: { kind: /invoices|service_invoices/, company: /[a-z0-9_]+/,
                                                                            number: /\d+/ }
              get 'records/:kind/:company/:number/document', to: 'records#document',
                                                             constraints: { kind: /invoices|service_invoices/, company: /[a-z0-9_]+/,
                                                                            number: /\d+/ }
              # pedido de venda: técnico e OS informados no chat (só no Chatwoot, para o relatório dos técnicos)
              scope 'records/sales/:company/:number', constraints: { company: /[a-z0-9_]+/, number: /\d+/ } do
                get 'attribution', to: 'sale_attributions#show'
                get 'attribution/preview', to: 'sale_attributions#preview'
                put 'attribution', to: 'sale_attributions#update'
                delete 'attribution', to: 'sale_attributions#destroy'
              end
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
