# OUTSIDER: envia uma figurinha da coleção do atendente numa conversa do WhatsApp.
#
# - Caixa da Evolution: vai direto na API (/message/sendSticker, arquivo em base64). A Evolution devolve a
#   mensagem enviada para a conversa (anexo .webp, source_id WAID:...), como faz com localização e
#   contato (Outsider::LocationSender). Esperamos esse eco por alguns segundos para marcar quem enviou e
#   a figurinha (content_attributes.outsider_sticker); se demorar, a figurinha aparece do mesmo jeito.
#   Não dá para criar a mensagem no Chatwoot e deixar a Evolution mandar: ela enviaria como foto (JPEG).
# - Caixa oficial (Channel::Whatsapp, whatsapp_cloud): a mensagem nasce no Chatwoot com o mesmo arquivo
#   (blob) da figurinha e content_attributes.outsider_sticker; Outsider::WhatsappCloudStickers faz a API
#   oficial mandar com type "sticker" em vez de "image".
class Outsider::StickerSender
  class Invalid < StandardError; end

  ECHO_WAIT = 6.seconds
  ECHO_INTERVAL = 0.4
  ATTRIBUTE = 'outsider_sticker'.freeze

  pattr_initialize [:conversation!, :user!, :sticker!]

  def self.cloud_inbox?(inbox)
    inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.try(:provider) == 'whatsapp_cloud'
  end

  def self.supported?(inbox)
    Outsider::EvolutionApi.evolution_inbox?(inbox) || cloud_inbox?(inbox)
  end

  def perform
    raise Invalid, 'not_supported' unless self.class.supported?(conversation.inbox)
    raise Invalid, 'no_file' unless sticker.file.attached?

    message = Outsider::EvolutionApi.evolution_inbox?(conversation.inbox) ? send_via_evolution : send_via_chatwoot
    Outsider::StickerLibrary.new(user: user, account: conversation.account).mark_used(sticker)
    message
  end

  private

  def attributes
    { ATTRIBUTE => { 'id' => sticker.id } }
  end

  def send_via_evolution
    encoded = sticker.file.blob.open { |file| Base64.strict_encode64(file.read) }
    response = Outsider::EvolutionApi.new(conversation.inbox).send_sticker(number: recipient, sticker: encoded)
    message_id = response.dig('key', 'id')
    attach_echo(message_id) if message_id.present?
  end

  def send_via_chatwoot
    params = ActionController::Parameters.new(content: '', private: false, attachments: [sticker.file.blob.signed_id],
                                              content_attributes: attributes)
    Messages::MessageBuilder.new(user, conversation, params).perform
  end

  # mesmo destino que a Evolution usa quando a mensagem sai do Chatwoot
  def recipient
    contact = conversation.contact
    contact.identifier.presence || contact.phone_number.to_s.delete('^0-9').presence || raise(Invalid, 'no_recipient')
  end

  def attach_echo(message_id)
    message = wait_for_echo("WAID:#{message_id}")
    return unless message

    message.update!(sender: user, content_attributes: message.content_attributes.merge(attributes))
    message
  end

  def wait_for_echo(source_id)
    deadline = ECHO_WAIT.from_now
    loop do
      message = Message.uncached { Message.find_by(inbox_id: conversation.inbox_id, source_id: source_id) }
      return message if message || Time.current > deadline

      sleep ECHO_INTERVAL
    end
  end
end
