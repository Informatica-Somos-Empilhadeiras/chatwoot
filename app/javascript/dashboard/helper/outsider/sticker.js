// OUTSIDER: figurinhas (stickers) do WhatsApp.
// - Reconhecer uma figurinha recebida: o WhatsApp manda figurinha sempre como webp e foto como jpeg, então
//   um anexo de imagem .webp sozinho (sem texto, fora o cabeçalho de quem mandou no grupo) é figurinha.
//   As que a gente envia ainda levam content_attributes.outsider_sticker.
// - Em que caixas dá para enviar: Evolution (webhook /chatwoot/webhook/) e a API oficial (whatsapp_cloud).
import { splitSenderHeader } from './mediaAlbum';

const WEBP_URL = /\.webp(\?|#|$)/i;
const EVOLUTION_WEBHOOK = /\/chatwoot\/webhook\//;

const fileTypeOf = attachment => attachment?.fileType ?? attachment?.file_type;
const contentTypeOf = attachment =>
  String(attachment?.contentType ?? attachment?.content_type ?? '');
const urlOf = attachment => attachment?.dataUrl ?? attachment?.data_url ?? '';

export const isStickerAttachment = attachment => {
  if (!attachment || fileTypeOf(attachment) !== 'image') return false;
  if (contentTypeOf(attachment).toLowerCase() === 'image/webp') return true;
  if (String(attachment.extension || '').toLowerCase() === 'webp') return true;
  return WEBP_URL.test(urlOf(attachment));
};

export const isStickerMessage = ({
  attachments,
  content,
  contentAttributes,
} = {}) => {
  if (!Array.isArray(attachments) || attachments.length !== 1) return false;
  if (contentAttributes?.outsiderSticker || contentAttributes?.outsider_sticker)
    return (
      isStickerAttachment(attachments[0]) ||
      fileTypeOf(attachments[0]) === 'image'
    );
  if (!isStickerAttachment(attachments[0])) return false;
  return !splitSenderHeader(content || '').body;
};

export const stickerUrlOf = attachment => urlOf(attachment);

export const supportsStickers = inbox =>
  EVOLUTION_WEBHOOK.test(inbox?.webhook_url || '') ||
  (inbox?.channel_type === 'Channel::Whatsapp' &&
    inbox?.provider === 'whatsapp_cloud');
