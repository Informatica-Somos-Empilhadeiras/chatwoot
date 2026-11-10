# OUTSIDER: o que o Chatwoot manda por webhook para a Evolution.
# - a mensagem nova vai com ela mesma em conversation.messages (ver Outsider::EvolutionApi.message_created_payload);
# - a mensagem que chegou do WhatsApp e a que só mudou (✓✓, lida, id do WhatsApp) não vão: a Evolution não
#   faz nada com elas e cada webhook segura uma vaga do Sidekiq por meio segundo ou mais, atrasando as
#   mensagens que precisam sair. A mensagem apagada continua indo, para a Evolution apagar no WhatsApp.
# Os webhooks da conta (Configurações > Integrações) continuam recebendo tudo.
# Encaixado no WebhookListener por config/initializers/outsider_message_delivery.rb.
module Outsider::EvolutionWebhooks
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return super unless Outsider::EvolutionApi.evolution_inbox?(message.inbox)
    return unless message.webhook_sendable?

    payload = Outsider::EvolutionApi.message_created_payload(message)
    deliver_account_webhooks(payload, message.inbox.account)
    deliver_api_inbox_webhooks(payload, message.inbox) unless message.incoming?
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return super unless Outsider::EvolutionApi.evolution_inbox?(message.inbox)
    return unless message.webhook_sendable?

    payload = message.webhook_data.merge(event: __method__.to_s)
    deliver_account_webhooks(payload, message.inbox.account)
    deliver_api_inbox_webhooks(payload, message.inbox) if message.content_attributes[:deleted]
  end
end
