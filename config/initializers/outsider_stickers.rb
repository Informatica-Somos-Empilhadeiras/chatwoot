# OUTSIDER: figurinhas do WhatsApp (ver app/services/outsider/sticker_library.rb e sticker_sender.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :stickers, only: [:index, :create, :update, :destroy] do
              post :send, action: :deliver, on: :member
            end
            resources :sticker_packs, only: [:create, :update, :destroy]
          end
        end
      end
    end
  end
end

Rails.application.config.to_prepare do
  service = Whatsapp::Providers::WhatsappCloudService
  service.prepend(Outsider::WhatsappCloudStickers) unless service < Outsider::WhatsappCloudStickers
end
