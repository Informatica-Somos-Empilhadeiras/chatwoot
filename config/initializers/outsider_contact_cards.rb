# OUTSIDER: enviar contato pelo WhatsApp (ver app/controllers/api/v1/accounts/outsider/contact_cards_controller.rb)
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            resources :contact_cards, only: [:create]
          end
        end
      end
    end
  end
end
