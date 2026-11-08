# OUTSIDER: aviso novo (push). Mensagem de cliente e avisos do Chatwoot (atribuição, citação) viram um DeliverJob.
# Incluído no AsyncDispatcher pelo config/initializers/outsider_push.rb, roda no Sidekiq.
class Outsider::PushListener < BaseListener
  def message_created(event)
    return unless Outsider::Push.enabled?

    message, = extract_message_and_account(event)
    return unless message.incoming? && !message.private?

    Outsider::Push::DeliverJob.perform_later('customer', message.id)
  end

  def notification_created(event)
    return unless Outsider::Push.enabled?

    notification = event.data[:notification]
    return unless notification && Outsider::Push::ChatwootNotice::TYPES.include?(notification.notification_type)

    Outsider::Push::DeliverJob.perform_later('notice', notification.id)
  end
end
