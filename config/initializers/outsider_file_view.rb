# OUTSIDER: visualizador de documentos das conversas (ver app/services/outsider/file_view.rb).
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            get 'file_views/:id', to: 'file_views#show'
            get 'file_views/:id/peek', to: 'file_views#peek'
          end
        end
      end
    end
  end

  get 'outsider/arquivo/:token/:filename', to: 'outsider/file_views#show', as: :outsider_file_view,
                                           constraints: { token: %r{[^/]+}, filename: %r{[^/]+} }
end
