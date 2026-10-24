# OUTSIDER: reagir e editar uma mensagem do WhatsApp pelo Chatwoot (Entrega 21), nas caixas da Evolution.
#
# Reagir: a Evolution manda a reação (/message/sendReaction) e devolve ao Chatwoot como mensagem nova, que
# vira o emoji no balão (Outsider::WhatsappMessageEcho). Reação vazia tira a do atendente: essa a Evolution
# não devolve, então a última reação da empresa na mensagem é marcada como removida aqui.
#
# Editar: só texto enviado pela empresa, até 15 minutos depois (limite do WhatsApp). Quem enviou ou um
# administrador edita. O texto muda no WhatsApp (/chat/updateMessage) e na mensagem do Chatwoot, marcada como
# editada; a assinatura de quem enviou, se a Evolution pôs, continua na frente.
class Outsider::WhatsappMessageActions
  class Invalid < StandardError; end

  EDIT_WINDOW = 15.minutes
  MAX_TEXT = 4096
  ECHO = Outsider::WhatsappMessageEcho

  pattr_initialize [:message!, :account_user!]

  def react(emoji)
    emoji = emoji.to_s.strip
    raise Invalid, 'invalid_emoji' unless emoji.empty? || ECHO.emoji?(emoji)

    record = whatsapp_record
    api.send_reaction(key: record['key'].slice('id', 'remoteJid', 'fromMe', 'participant').compact, reaction: emoji)
    remove_own_reaction if emoji.empty?
  end

  def edit(text)
    text = text.to_s.strip
    raise Invalid, 'not_editable' unless editable?
    raise Invalid, 'invalid_text' if text.empty? || text.length > MAX_TEXT

    record = whatsapp_record
    sent = whatsapp_text(record, text)
    api.update_message(number: record.dig('key', 'remoteJid'), key: record['key'].slice('id', 'remoteJid', 'fromMe'), text: sent)
    attributes = message.content_attributes.merge(ECHO::EDITED_AT => Time.current.iso8601, ECHO::EDIT_SENT => sent)
    message.update!(content: text, content_attributes: attributes)
    message
  end

  private

  def api
    @api ||= begin
      raise Invalid, 'not_evolution' unless Outsider::EvolutionApi.evolution_inbox?(message.inbox)
      raise Invalid, 'not_available' if message.private? || message.content_attributes[:deleted] || !(message.incoming? || message.outgoing?)

      Outsider::EvolutionApi.new(message.inbox)
    end
  end

  def whatsapp_record
    Outsider::WhatsappMessageKey.new(message, api).record || raise(Invalid, 'not_found')
  end

  def editable?
    message.outgoing? && message.attachments.empty? && message.content.present? && message.created_at > EDIT_WINDOW.ago &&
      (message.sender == account_user.user || account_user.administrator?)
  end

  # o texto que está no WhatsApp termina com o do Chatwoot; o que vem antes (assinatura) continua
  def whatsapp_text(record, text)
    current = Outsider::WhatsappMessageKey.text_of(record)
    old = Outsider::WhatsappMessageKey.whatsapp_text(message.content)
    prefix = current.end_with?(old) ? current.delete_suffix(old) : ''
    "#{prefix}#{Outsider::WhatsappMessageKey.whatsapp_text(text)}"
  end

  # content_attributes é gravado como texto JSON dentro da coluna json
  def remove_own_reaction
    reaction = message.conversation.messages.outgoing.where("(content_attributes #>> '{}')::jsonb ->> 'in_reply_to' = ?", message.id.to_s)
                      .order(id: :desc).find { |candidate| candidate.content_attributes[ECHO::REACTION] }
    return unless reaction

    reaction.update!(content_attributes: reaction.content_attributes.merge(
      ECHO::REACTION => reaction.content_attributes[ECHO::REACTION].merge('removed' => true)
    ))
  end
end
