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
              end
              resource :status, only: [:show]
              resources :service_orders, only: [:index] do
                collection do
                  get :board
                  put :substatus
                  put :field
                end
              end
              resources :customers, only: [:index]
              resource :contact_link, only: [:create, :destroy]
              resources :quotes, only: [:index]
            end
          end
        end
      end
    end
  end
end
