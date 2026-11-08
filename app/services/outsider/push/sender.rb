# OUTSIDER: manda um aviso para todos os navegadores (computador e celular) em que a pessoa ativou o push. Usa as mesmas
# chaves VAPID e a mesma tabela de aparelhos do Chatwoot (notification_subscriptions); aparelho vencido é apagado.
class Outsider::Push::Sender
  def initialize(user)
    @user = user
  end

  def subscriptions
    @user.notification_subscriptions.browser_push
  end

  def deliver(payload)
    return 0 unless VapidService.public_key

    message = JSON.generate(payload)
    subscriptions.count { |subscription| send_to(subscription, message) }
  end

  private

  def send_to(subscription, message)
    attributes = subscription.subscription_attributes
    WebPush.payload_send(
      message: message, endpoint: attributes['endpoint'], p256dh: attributes['p256dh'], auth: attributes['auth'],
      ttl: 6.hours.to_i, urgency: 'high',
      vapid: { subject: Outsider::Push.site.presence || 'mailto:suporte@localhost', public_key: VapidService.public_key,
               private_key: VapidService.private_key },
      ssl_timeout: 5, open_timeout: 5, read_timeout: 5
    )
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized
    subscription.destroy!
    false
  rescue StandardError => e
    Rails.logger.warn("[outsider push] #{@user.id}: #{e.class} #{e.message}")
    false
  end
end
