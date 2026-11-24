# OUTSIDER: Aplicativos (blocos Microsoft e Google do menu). Microsoft: Outlook e OneDrive com o login do "Conectar meu
# Teams" (a Agenda usa as rotas da agenda do Teams, teams_calendar, em outsider_teams.rb). Google: Gmail, Agenda e Drive
# com a conta Google de cada pessoa (Configurações > Google). Tudo é espelho: as telas pedem à Microsoft/Google na hora e
# nada de e-mail, evento ou arquivo fica no Chatwoot.
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
              scope 'google' do
                get 'account', to: 'google_account#show'
                put 'account/app', to: 'google_account#save_app'
                post 'account/authorize', to: 'google_account#authorize'
                post 'account/finish', to: 'google_account#finish'
                delete 'account', to: 'google_account#disconnect'
                delete 'account/links/:link_id', to: 'google_account#destroy_link'
                get 'mail/folders', to: 'google_mail#folders'
                get 'mail/messages', to: 'google_mail#index'
                post 'mail/messages', to: 'google_mail#create'
                get 'mail/messages/:id', to: 'google_mail#show', constraints: { id: %r{[^/]+} }
                patch 'mail/messages/:id', to: 'google_mail#update', constraints: { id: %r{[^/]+} }
                post 'mail/messages/:id/move', to: 'google_mail#move', constraints: { id: %r{[^/]+} }
                get 'drive/items', to: 'google_drive#index'
                post 'drive/items', to: 'google_drive#create'
                post 'drive/folders', to: 'google_drive#create_folder'
                get 'drive/items/:id', to: 'google_drive#show', constraints: { id: %r{[^/]+} }
                get 'drive/items/:id/preview', to: 'google_drive#preview', constraints: { id: %r{[^/]+} }
                get 'drive/items/:id/download', to: 'google_drive#download', constraints: { id: %r{[^/]+} }
                post 'drive/items/:id/share', to: 'google_drive#share', constraints: { id: %r{[^/]+} }
                delete 'drive/items/:id', to: 'google_drive#destroy', constraints: { id: %r{[^/]+} }
                get 'calendar/events', to: 'google_calendar#index'
                post 'calendar/events', to: 'google_calendar#create'
                delete 'calendar/events/:id', to: 'google_calendar#destroy', constraints: { id: %r{[^/]+} }
                get 'calendar/people', to: 'google_calendar#people'
              end
            end
          end
        end
      end
    end
  end

  get 'outsider/apps/file', to: 'outsider/apps_files#show'
  # o mesmo, com o nome do arquivo no fim do endereço (o visualizador do Office na web olha a extensão)
  get 'outsider/apps/file/:name', to: 'outsider/apps_files#show', constraints: { name: %r{[^/]+} }, format: false
  get 'outsider/google/oauth/callback', to: 'outsider/google_oauth#callback'
end

# OUTSIDER: observador do Gmail (a cada 5 minutos, e-mail novo na Principal vira aviso na tela e push). Job criado um a um
# (create), nunca com load_from_hash!, que apagaria os agendamentos do schedule.yml.
Rails.application.reloader.to_prepare do
  if Sidekiq.server?
    Sidekiq::Cron::Job.create(name: 'outsider_google_watch_job', cron: '*/5 * * * *', class: 'Outsider::Apps::Google::WatchJob',
                              queue: 'scheduled_jobs')
  end
end
