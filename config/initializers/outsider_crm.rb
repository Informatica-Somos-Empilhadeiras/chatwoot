# OUTSIDER: rotas do CRM (ver app/models/outsider/crm.rb e app/controllers/api/v1/accounts/outsider/crm/)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            namespace :crm do
              resource :access, only: [:show]
              resource :settings, only: [:show, :update]
              resources :business_units, only: [:index, :show, :create, :update, :destroy] do
                resources :members, controller: 'business_unit_members', only: [:create, :update, :destroy]
              end
              resources :pipelines, only: [:index, :show, :create, :update, :destroy]
              resources :lost_reasons, only: [:index, :create, :update, :destroy]
              resources :custom_fields, only: [:index, :create, :update, :destroy]
              resources :opportunities, only: [:index, :show, :create, :update, :destroy]
            end
          end
        end
      end
    end
  end
end
