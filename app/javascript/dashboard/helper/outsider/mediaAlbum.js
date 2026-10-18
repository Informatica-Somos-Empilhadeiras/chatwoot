// OUTSIDER: álbum de fotos e vídeos estilo WhatsApp.
// Mensagens seguidas só com mídia (sem texto), do mesmo remetente e enviadas
// com pouco intervalo viram uma única mensagem com todos os anexos. O
// Message.vue desenha essa mensagem com o MediaAlbum.vue.
// As mensagens aqui já estão em camelCase (vêm do MessageList.vue).
//
// Nos grupos, a Evolution API coloca quem enviou no texto ("**+55 ... - Nome:**").
// Esse cabeçalho não conta como legenda: separa os álbuns por participante e
// aparece em cima do álbum. Foto avulsa de grupo também usa o álbum (1 item).

export const ALBUM_MIN_ITEMS = 2;
export const ALBUM_MAX_GAP_SECONDS = 60;

const MEDIA_TYPES = ['image', 'video'];
const ALBUM_MESSAGE_TYPES = [0, 1]; // incoming, outgoing
const BLOCKED_STATUSES = ['failed', 'progress'];

const SENDER_HEADER_REGEX = /^\*\*([^*\n]+?):?\*\*:?\s*([\s\S]*)$/;

const isMediaAttachment = attachment =>
  MEDIA_TYPES.includes(attachment?.fileType);

export const splitSenderHeader = content => {
  const match = content?.match(SENDER_HEADER_REGEX);
  if (match) return { header: match[1], body: match[2].trim() };
  return { header: null, body: content?.trim() || '' };
};

export const isMediaAlbum = ({ content, attachments } = {}) => {
  const { header, body } = splitSenderHeader(content);
  const minItems = header ? 1 : ALBUM_MIN_ITEMS;
  return (
    !body &&
    Array.isArray(attachments) &&
    attachments.length >= minItems &&
    attachments.every(isMediaAttachment)
  );
};

const isAlbumCandidate = message =>
  ALBUM_MESSAGE_TYPES.includes(message.messageType) &&
  !message.private &&
  !splitSenderHeader(message.content).body &&
  !message.contentAttributes?.deleted &&
  !message.contentAttributes?.inReplyTo &&
  !BLOCKED_STATUSES.includes(message.status) &&
  Array.isArray(message.attachments) &&
  message.attachments.length > 0 &&
  message.attachments.every(isMediaAttachment);

const senderIdOf = message => message.senderId ?? message.sender?.id;

const belongsToSameAlbum = (previous, current, firstUnreadId) =>
  current.id !== firstUnreadId &&
  senderIdOf(previous) === senderIdOf(current) &&
  previous.messageType === current.messageType &&
  splitSenderHeader(previous.content).header ===
    splitSenderHeader(current.content).header &&
  current.createdAt - previous.createdAt <= ALBUM_MAX_GAP_SECONDS;

const toAlbum = run => {
  const attachments = run.flatMap(message => message.attachments);
  if (run.length < 2 || attachments.length < ALBUM_MIN_ITEMS) return run;
  return [{ ...run[0], attachments }];
};

/**
 * Junta mensagens seguidas só com mídia em uma mensagem-álbum.
 * Um álbum nunca atravessa o marcador de "não lidas" (firstUnreadId).
 */
export const groupMediaAlbums = (messages = [], firstUnreadId = null) => {
  const result = [];
  let run = [];

  const flush = () => {
    result.push(...toAlbum(run));
    run = [];
  };

  messages.forEach(message => {
    if (!isAlbumCandidate(message)) {
      flush();
      result.push(message);
      return;
    }
    const previous = run[run.length - 1];
    if (previous && !belongsToSameAlbum(previous, message, firstUnreadId)) {
      flush();
    }
    run.push(message);
  });
  flush();

  return result;
};
