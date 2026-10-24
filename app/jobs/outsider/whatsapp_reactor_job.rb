# OUTSIDER: quem reagiu numa conversa de grupo (Entrega 21). A reação chega ao Chatwoot pela conversa do
# grupo, sem o participante; a Evolution guarda a mensagem logo depois de mandá-la, com o participante e o
# nome do WhatsApp (pushName). Se a mensagem não for reação (era uma resposta só com emoji), ela volta a
# aparecer como mensagem. Ver Outsider::WhatsappMessageEcho.
class Outsider::WhatsappReactorJob < ApplicationJob
  class NotSaved < StandardError; end

  WAIT = 3.seconds
  REACTION = Outsider::WhatsappMessageEcho::REACTION

  queue_as :default
  retry_on NotSaved, wait: 5.seconds, attempts: 3
  discard_on Outsider::EvolutionApi::Error

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message&.content_attributes&.dig(REACTION)

    record = Outsider::EvolutionApi.new(message.inbox)
                                   .find_messages({ key: { id: message.source_id.delete_prefix('WAID:') } }, page: 1, offset: 1)['records'].first
    raise NotSaved unless record

    message.update!(content_attributes: attributes_for(message, record))
  end

  private

  def attributes_for(message, record)
    return message.content_attributes.except(REACTION) unless record['messageType'] == 'reactionMessage'

    jid = record.dig('key', 'participantAlt').presence || record.dig('key', 'participant').to_s
    phone = jid.end_with?('@s.whatsapp.net') ? jid.split('@').first.split(':').first : nil
    from = { 'jid' => jid, 'name' => record['pushName'].presence, 'phone' => phone }.compact
    message.content_attributes.merge(REACTION => message.content_attributes[REACTION].merge('from' => from))
  end
end
