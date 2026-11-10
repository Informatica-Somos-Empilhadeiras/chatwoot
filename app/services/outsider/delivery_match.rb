# OUTSIDER: qual mensagem do WhatsApp é de qual mensagem do Chatwoot, na conferência de entrega (ver
# Outsider::DeliveryCheck). A Evolution não diz, então vale o que dá para ver dos dois lados:
# 1. a de mesmo texto (o do WhatsApp pode ter a assinatura de quem enviou na frente) ou, na mensagem com
#    anexos, um arquivo para cada anexo;
# 2. para a mensagem com o prazo vencido que ficou sem par, a que saiu depois dela dentro do prazo (o texto
#    pode ter saído diferente do que o Chatwoot guardou).
# Cada mensagem do WhatsApp fica com a mensagem do Chatwoot enviada por último antes dela. Assim, quando o
# agente repete o texto de uma mensagem que falhou, é a repetida que aparece como enviada, e a que falhou
# continua como falha.
class Outsider::DeliveryMatch
  # diferença de relógio aceita entre o Chatwoot e a Evolution
  SKEW = 10.seconds
  MEDIA_TYPES = %w[imageMessage videoMessage audioMessage documentMessage documentWithCaptionMessage stickerMessage ptvMessage].freeze

  # quantas mensagens do WhatsApp a mensagem vira: cada anexo sai como uma
  def self.wanted(message)
    [message.attachments.size, 1].max
  end

  # messages: as mensagens de uma conversa; records: as enviadas pela empresa nesse chat que ainda não são
  # de nenhuma mensagem, da mais antiga para a mais nova; deadlines: { id da mensagem => fim do prazo dela }
  def initialize(messages, records, deadlines)
    @messages = messages.sort_by { |message| Outsider::DeliveryCheck.since(message) }.reverse
    @records = records
    @deadlines = deadlines
    @found = Hash.new { |hash, id| hash[id] = [] }
  end

  # { id da mensagem => as mensagens do WhatsApp dela }
  def found
    assign(@messages) { |record, message| same_content?(record, message) }
    @exact = @found.values.any?(&:any?)
    assign(@messages.select { |message| @deadlines[message.id].past? }) do |record, message|
      record['messageTimestamp'].to_i <= @deadlines[message.id].to_i
    end
    @found
  end

  # achou alguma pelo texto ou pelo arquivo: a conferência funciona nesta caixa
  def exact?
    @exact
  end

  private

  def assign(messages)
    (@records - @found.values.flatten).each do |record|
      sent_at = record['messageTimestamp'].to_i
      message = messages.find do |candidate|
        @found[candidate.id].size < self.class.wanted(candidate) && sent_at >= (Outsider::DeliveryCheck.since(candidate) - SKEW).to_i &&
          yield(record, candidate)
      end
      @found[message.id] << record if message
    end
  end

  def same_content?(record, message)
    return MEDIA_TYPES.include?(record['messageType']) if message.attachments.any?

    text = Outsider::WhatsappMessageKey.whatsapp_text(message.webhook_content).strip
    text.present? && Outsider::WhatsappMessageKey.text_of(record).strip.end_with?(text)
  end
end
