# OUTSIDER: automação por bot desenhada como fluxograma (ver app/services/outsider/bot/runner.rb e
# app/controllers/api/v1/accounts/outsider/bot_flows_controller.rb)
Rails.application.config.to_prepare do
  AsyncDispatcher.prepend(Outsider::BotDispatcher) unless AsyncDispatcher < Outsider::BotDispatcher
end

Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :bot_flows, only: [:index, :show, :create, :update, :destroy] do
              post :duplicate, on: :member
            end
          end
        end
      end
    end
  end
end
