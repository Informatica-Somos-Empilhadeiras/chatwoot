# OUTSIDER: página Status do WhatsApp (ver app/controllers/api/v1/accounts/outsider/whatsapp_statuses_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :whatsapp_statuses, only: [:index, :create] do
              collection do
                get :inboxes
                get :mine
                get :media
                get :audience
                post :republish
                get :permissions
                patch :permissions, action: :update_permission
              end
            end
          end
        end
      end
    end
  end
end

Rails.application.config.to_prepare do
  Message.prepend(Outsider::MessageReplyLink) unless Message < Outsider::MessageReplyLink
end
