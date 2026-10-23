# OUTSIDER: mensagem e conversa novas vão para a tela na hora, sem passar pela fila do Sidekiq.
#
# O Chatwoot manda todo aviso em tempo real por um job (ActionCableBroadcastJob). Quando o Sidekiq está
# ocupado (webhooks para a Evolution esperando até 5 s cada, avatares, CRM), a mensagem que a Evolution
# acabou de gravar fica parada na fila e aparece para o agente segundos depois. Estes dois avisos saem
# direto do processo que gravou a mensagem: é só um PUBLISH no Redis por agente da caixa.
# Encaixado no ActionCableListener por config/initializers/outsider_message_delivery.rb.
module Outsider::InstantBroadcast
  EVENTS = [Events::Types::MESSAGE_CREATED, Events::Types::CONVERSATION_CREATED].freeze

  private

  def broadcast(account, tokens, event_name, data)
    return super unless EVENTS.include?(event_name)
    return if tokens.blank?

    payload = data.merge(account_id: account.id)
    payload[:performer] = Current.user&.push_event_data if Current.user.present?
    ::ActionCableBroadcastJob.perform_now(tokens.uniq, event_name, payload)
  end
end
