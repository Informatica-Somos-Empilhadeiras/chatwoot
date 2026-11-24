# OUTSIDER: Aplicativos (blocos Microsoft e Google do menu): Outlook e OneDrive com o login do "Conectar meu Teams".
# Tudo é espelho: as telas pedem à Microsoft na hora e nada de e-mail ou arquivo fica no Chatwoot. A Agenda usa as rotas
# da agenda do Teams (teams_calendar, em outsider_teams.rb).
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            namespace :apps do
              get 'summary', to: 'summary#show'
              scope 'microsoft' do
                get 'mail/folders', to: 'microsoft_mail#folders'
                get 'mail/messages', to: 'microsoft_mail#index'
                post 'mail/messages', to: 'microsoft_mail#create'
                get 'mail/messages/:id', to: 'microsoft_mail#show', constraints: { id: %r{[^/]+} }
                patch 'mail/messages/:id', to: 'microsoft_mail#update', constraints: { id: %r{[^/]+} }
                post 'mail/messages/:id/move', to: 'microsoft_mail#move', constraints: { id: %r{[^/]+} }
                get 'drive/items', to: 'microsoft_drive#index'
                post 'drive/items', to: 'microsoft_drive#create'
                post 'drive/folders', to: 'microsoft_drive#create_folder'
                get 'drive/items/:id', to: 'microsoft_drive#show', constraints: { id: %r{[^/]+} }
                get 'drive/items/:id/preview', to: 'microsoft_drive#preview', constraints: { id: %r{[^/]+} }
                get 'drive/items/:id/download', to: 'microsoft_drive#download', constraints: { id: %r{[^/]+} }
                post 'drive/items/:id/share', to: 'microsoft_drive#share', constraints: { id: %r{[^/]+} }
                delete 'drive/items/:id', to: 'microsoft_drive#destroy', constraints: { id: %r{[^/]+} }
              end
            end
          end
        end
      end
    end
  end

  get 'outsider/apps/file', to: 'outsider/apps_files#show'
end
