# OUTSIDER: na API oficial do WhatsApp, a mensagem marcada como figurinha (content_attributes.outsider_sticker,
# ver Outsider::StickerSender) sai com type "sticker" em vez de "image", senão chega como foto. Encaixado em
# Whatsapp::Providers::WhatsappCloudService (config/initializers/outsider_stickers.rb).
module Outsider::WhatsappCloudStickers
  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    return super unless message.content_attributes[Outsider::StickerSender::ATTRIBUTE].present? && attachment&.file_type == 'image'

    response = HTTParty.post(
      "#{phone_id_path('v24.0')}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        type: 'sticker',
        sticker: { link: attachment.download_url }
      }.to_json
    )
    process_response(response, message)
  end
end
