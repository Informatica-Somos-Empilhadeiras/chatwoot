// OUTSIDER: avisos que a Evolution escreve no Chatwoot (Entrega 21): erro de envio e número sem WhatsApp
// (nota interna na conversa) e a situação da conexão e da importação (na conversa do robô da Evolution). Eles
// vêm na língua da Evolution (LANGUAGE: en, pt-BR ou es); aqui o texto é reconhecido nas três e a bolha
// mostra o aviso traduzido, com a cor e o emoji do tipo (NoticeBubble.vue).

const NOTICES = [
  {
    type: 'NUMBER_NOT_ON_WHATSAPP',
    level: 'error',
    patterns: [
      /não é um número válido do WhatsApp/i,
      /not a valid Whatsapp number/i,
      /no es un número de Whatsapp válido/i,
    ],
  },
  {
    type: 'NOT_SENT',
    level: 'error',
    patterns: [
      /^🚨 Não foi possível enviar a mensagem\. Verifique sua conexão\.(?<detail>[\s\S]*)$/,
      /^🚨 The message could not be sent\. Please check your connection\.(?<detail>[\s\S]*)$/,
      /^🚨 El mensaje no se pudo enviar\. Comprueba tu conexión\.(?<detail>[\s\S]*)$/,
    ],
  },
  {
    type: 'DISCONNECTED',
    level: 'error',
    patterns: [
      /^🚨 Instância \*(?<inbox>.+?)\* desconectada do WhatsApp/,
      /^🚨 Disconnecting WhatsApp from inbox \*(?<inbox>.+?)\*/,
      /^🚨 Instancia \*(?<inbox>.+?)\* desconectado de Whatsapp/,
    ],
  },
  {
    type: 'ALREADY_CONNECTED',
    level: 'info',
    patterns: [
      /^🚨 Instância \*(?<inbox>.+?)\* já está conectada/,
      /^🚨 (?<inbox>.+?) instance is connected/,
      /^🚨 La instancia (?<inbox>.+?) está conectada/,
    ],
  },
  {
    type: 'CONNECTED',
    level: 'success',
    patterns: [
      /^🚀 Conectado com sucesso/,
      /^🚀 Connection successfully established/,
      /^🚀 ¡Conexión establecida exitosamente/,
    ],
  },
  {
    type: 'CACHE_CLEARED',
    level: 'success',
    patterns: [
      /^✅ Instância \*(?<inbox>.+?)\* cache removido/,
      /^✅ (?<inbox>.+?) instance cache cleared/,
    ],
  },
  {
    type: 'INSTANCE_NOT_FOUND',
    level: 'warning',
    patterns: [
      /^⚠️ Instância \*(?<inbox>.+?)\* não encontrada/,
      /^⚠️ (?<inbox>.+?) instance not found/,
      /^⚠️ Instancia (?<inbox>.+?) no encontrada/,
    ],
  },
  {
    type: 'INSTANCE_STATUS',
    level: 'info',
    patterns: [
      /^⚠️ Status da instância (?<inbox>.+?): \*(?<state>.+?)\*/,
      /^⚠️ (?<inbox>.+?) instance status: \*(?<state>.+?)\*/,
      /^⚠️ Estado de la instancia (?<inbox>.+?): \*(?<state>.+?)\*/,
    ],
  },
  {
    type: 'IMPORT_STARTED',
    level: 'info',
    patterns: [
      /^💬 Iniciando importação de mensagens/,
      /^💬 Starting to import messages/,
    ],
  },
  {
    type: 'IMPORTING',
    level: 'info',
    patterns: [/^💬 Importando mensagens/, /^💬 Importing messages/],
  },
  {
    type: 'IMPORTED',
    level: 'success',
    patterns: [
      /^💬 (?<count>\d+) mensagens importadas/,
      /^💬 (?<count>\d+) messages imported/,
    ],
  },
  {
    type: 'IMPORT_FAILED',
    level: 'warning',
    patterns: [
      /^💬 Não foi possível importar as mensagens/,
      /^💬 Something went wrong in importing messages/,
    ],
  },
  {
    type: 'QR_LIMIT',
    level: 'warning',
    patterns: [
      /^Limite de geração de QRCode atingido/,
      /^QRCode generation limit reached/,
    ],
  },
];

// motivos mais comuns que a Evolution põe no fim do erro de envio ("_Error: Connection Closed_")
const DETAILS = [
  { key: 'CONNECTION_CLOSED', pattern: /connection closed|conexão fechada/i },
  { key: 'TIMEOUT', pattern: /timed? ?out/i },
  { key: 'INSTANCE_NOT_FOUND', pattern: /instance not found/i },
  { key: 'LOGGED_OUT', pattern: /not-authorized|logged ?out/i },
  { key: 'RATE_LIMIT', pattern: /rate-overlimit/i },
];

const cleanDetail = text =>
  String(text || '')
    .trim()
    .replace(/^_+|_+$/g, '')
    .trim();

/**
 * Aviso da Evolution reconhecido no texto da mensagem, ou null.
 * { type, level: 'error'|'warning'|'success'|'info', inbox, state, count, detail, detailKey }
 */
export const evolutionNoticeOf = ({ content, attachments } = {}) => {
  if (!content || attachments?.length) return null;
  const text = content.trim();
  let found = null;
  NOTICES.some(notice =>
    notice.patterns.some(pattern => {
      const match = text.match(pattern);
      if (match) found = { notice, groups: match.groups || {} };
      return Boolean(match);
    })
  );
  if (!found) return null;

  const { notice, groups } = found;
  const detail = cleanDetail(groups.detail);
  return {
    type: notice.type,
    level: notice.level,
    inbox: groups.inbox || '',
    state: groups.state || '',
    count: groups.count || '',
    detail,
    detailKey: DETAILS.find(item => item.pattern.test(detail))?.key || null,
  };
};
