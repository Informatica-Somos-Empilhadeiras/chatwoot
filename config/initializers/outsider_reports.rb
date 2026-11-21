# OUTSIDER: rotas dos relatórios da seção ERP (um controlador por relatório em
# app/controllers/api/v1/accounts/outsider/reports/). Mudou rota: reiniciar o Rails.
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            namespace :reports do
              # desempenho dos técnicos: pedidos faturados com o técnico informado no chat
              resource :technicians, only: [:show, :update]
            end
          end
        end
      end
    end
  end
end
