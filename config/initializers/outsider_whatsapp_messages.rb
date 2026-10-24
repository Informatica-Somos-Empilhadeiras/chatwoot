# OUTSIDER: reações e edições do WhatsApp (ver app/models/outsider/whatsapp_message_echo.rb e
# app/controllers/api/v1/accounts/outsider/whatsapp_messages_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :whatsapp_messages, only: [:update] do
              member { post :reaction }
            end
          end
        end
      end
    end
  end
end

Rails.application.config.to_prepare do
  Message.include(Outsider::WhatsappMessageEcho) unless Message < Outsider::WhatsappMessageEcho
end
