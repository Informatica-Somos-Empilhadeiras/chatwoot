# OUTSIDER: acha na Evolution a mensagem do WhatsApp de uma mensagem do Chatwoot (Entrega 21), para reagir e
# editar. A que veio do WhatsApp tem o id no source_id ("WAID:<id>"). A que saiu do Chatwoot a Evolution não
# devolve: procura a enviada pela empresa no mesmo chat, logo depois, com o mesmo texto (o da Evolution pode
# ter a assinatura de quem enviou na frente). Achada, o id fica no source_id para as próximas vezes.
class Outsider::WhatsappMessageKey
  WINDOW = 2.minutes
  PAGE_SIZE = 100

  def initialize(message, api)
    @message = message
    @api = api
  end

  # Devolve o registro da Evolution ({ 'key' => {...}, 'message' => {...}, ... }) ou nil
  def record
    @record ||= by_source_id || by_content
  end

  def self.text_of(record)
    message = record['message'] || {}
    message['conversation'] || message.dig('extendedTextMessage', 'text') || ''
  end

  # mesma troca de formatação que a Evolution faz no texto que sai do Chatwoot
  def self.whatsapp_text(content)
    content.to_s
           .gsub(/(?<!\*)\*((?!\s)([^\n*]+?)(?<!\s))\*(?!\*)/, '_\1_')
           .gsub(/\*{2}((?!\s)([^\n*]+?)(?<!\s))\*{2}/, '*\1*')
           .gsub(/~{2}((?!\s)([^\n*]+?)(?<!\s))~{2}/, '~\1~')
           .gsub(/(?<!`)`((?!\s)([^`*]+?)(?<!\s))`(?!`)/, '```\1```')
  end

  private

  def by_source_id
    return unless @message.source_id.to_s.start_with?('WAID:')

    @api.find_messages({ key: { id: @message.source_id.delete_prefix('WAID:') } }, page: 1, offset: 1)['records'].first
  end

  def by_content
    return unless @message.outgoing? && @message.content.present?

    text = self.class.whatsapp_text(@message.content)
    found = sent_around_creation.find { |record| same_chat?(record) && self.class.text_of(record).end_with?(text) }
    @message.update!(source_id: "WAID:#{found.dig('key', 'id')}") if found
    found
  end

  def sent_around_creation
    range = { gte: (@message.created_at - 30.seconds).iso8601, lte: (@message.created_at + WINDOW).iso8601 }
    @api.find_messages({ key: { fromMe: true }, messageTimestamp: range }, page: 1, offset: PAGE_SIZE)['records']
  end

  # o chat do contato: o identificador da Evolution (grupo ou número@s.whatsapp.net) ou, sem ele, o telefone;
  # no Brasil o WhatsApp pode ter o número sem o 9 da frente
  def same_chat?(record)
    jid = record.dig('key', 'remoteJid').to_s
    contact = @message.conversation.contact
    return true if contact.identifier.present? && jid == contact.identifier

    digits = jid.split('@').first.to_s
    phone = contact.phone_number.to_s.delete('^0-9')
    phone.present? && (digits == phone || digits == phone.sub(/\A(55\d{2})9(\d{8})\z/, '\1\2'))
  end
end
