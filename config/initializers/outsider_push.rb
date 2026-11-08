# OUTSIDER: aviso novo no navegador e no celular (ver app/services/outsider/push.rb). Ouvinte das mensagens e avisos do
# Chatwoot, troca do push do navegador do Chatwoot pelo novo e as rotas da tela Configurações > Notificações.
Rails.application.config.to_prepare do
  unless Notification::PushNotificationService < Outsider::Push::ReplaceBrowserPush
    Notification::PushNotificationService.prepend(Outsider::Push::ReplaceBrowserPush)
  end

  # o event_handlers.rb roda antes deste arquivo e já registrou os ouvintes sem este: registra aqui
  async = Rails.configuration.try(:dispatcher)&.async_dispatcher
  # (pelo nome da classe: no dev, depois de recarregar o código, não registra de novo)
  if async
    listeners = async.send(:local_registrations).map { |registration| registration.listener.class.name }
    async.subscribe(Outsider::PushListener.instance) if listeners.exclude?('Outsider::PushListener')
  end
end

Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            get 'push', to: 'push#show'
            patch 'push', to: 'push#update'
            post 'push/devices', to: 'push#register'
            delete 'push/devices/:device_id', to: 'push#unregister'
            post 'push/permission', to: 'push#permission'
            post 'push/test', to: 'push#test'
            post 'push/remind/:user_id', to: 'push#remind'
          end
        end
      end
    end
  end

  # "Marcar como lida" no próprio aviso (token assinado, sem a sessão da pessoa)
  post 'outsider/push/read', to: 'outsider/push_read#create'
end
