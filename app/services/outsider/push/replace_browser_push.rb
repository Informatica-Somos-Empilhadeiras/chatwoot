# OUTSIDER: o push novo substitui o push do Chatwoot no navegador (ninguém recebe aviso repetido da mesma mensagem). O
# push do app de celular do Chatwoot (FCM) continua igual. Incluído no Notification::PushNotificationService pelo
# config/initializers/outsider_push.rb; com OUTSIDER_PUSH=off volta o push do Chatwoot.
module Outsider::Push::ReplaceBrowserPush
  private

  def send_browser_push(subscription)
    return if Outsider::Push.enabled?

    super
  end
end
