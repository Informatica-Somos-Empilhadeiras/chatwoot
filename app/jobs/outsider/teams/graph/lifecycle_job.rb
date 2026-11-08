# OUTSIDER: aviso de ciclo de vida da Microsoft sobre uma assinatura do "Conectar meu Teams": pedir de novo
# (reauthorizationRequired) renova com o token da pessoa; removida (subscriptionRemoved) cria outra.
class Outsider::Teams::Graph::LifecycleJob < ApplicationJob
  queue_as :default

  def perform(subscription_id, event)
    subscription = Outsider::TeamsSubscription.includes(:link).find_by(id: subscription_id)
    return if subscription.nil? || subscription.link.status != 'active'

    subscriptions = Outsider::Teams::Graph::Subscriptions.new(subscription.link)
    case event.to_s
    when 'reauthorizationRequired' then subscriptions.renew(subscription)
    when 'subscriptionRemoved'
      subscription.update!(subscription_id: nil, expires_at: nil)
      subscriptions.create(subscription)
    end
  rescue Outsider::Teams::Graph::Client::Error => e
    subscription&.update(last_error: e.message.first(250))
  end
end
