// OUTSIDER: funções da página Status do WhatsApp.
import { format, fromUnixTime, isToday, isYesterday } from 'date-fns';
import { parsePhoneNumberFromString } from 'libphonenumber-js';
import { LocalStorage } from 'shared/helpers/localStorage';
import WhatsappStatusAPI from 'dashboard/api/outsider/whatsappStatus';

export const STATUS_LIFETIME = 24 * 60 * 60;
export const TEXT_MAX_LENGTH = 700;
export const FILE_RULES = {
  image: { types: ['image/jpeg', 'image/png'], maxSize: 5 * 1024 * 1024 },
  video: { types: ['video/mp4'], maxSize: 16 * 1024 * 1024 },
};
export const FONTS = { DEFAULT: 1, SCRIPT: 2 };
// cores de fundo do status de texto, as mesmas do WhatsApp
export const BACKGROUND_COLORS = [
  '#128C7E',
  '#54C265',
  '#26C4DC',
  '#5696FF',
  '#8294CA',
  '#6E267D',
  '#A62C71',
  '#792138',
  '#FF7B6B',
  '#F0B330',
  '#AE8774',
  '#243640',
];

const SEEN_STORE = 'outsider_whatsapp_status_seen';
const LAYOUT_STORE = 'outsider_whatsapp_status_layout';
const CONTACTS_LAYOUT_STORE = 'outsider_whatsapp_status_contacts_layout';

const nowInSeconds = () => Math.floor(Date.now() / 1000);

export const isActive = status =>
  !status.deleted && nowInSeconds() - status.timestamp < STATUS_LIFETIME;

export const hoursLeft = status =>
  Math.max(
    1,
    Math.ceil((status.timestamp + STATUS_LIFETIME - nowInSeconds()) / 3600)
  );

export const hasMedia = status => ['image', 'video'].includes(status.type);

export const canRepublish = status =>
  !status.deleted && ['text', 'image', 'video'].includes(status.type);

// a Evolution não guarda a cor do status de texto, então cada status ganha uma cor fixa
export const colorFor = id =>
  BACKGROUND_COLORS[
    Array.from(id).reduce(
      (hash, char) => (hash * 31 + char.charCodeAt(0)) % 100003,
      7
    ) % BACKGROUND_COLORS.length
  ];

export const timeLabel = (t, timestamp) => {
  const date = fromUnixTime(timestamp);
  const time = format(date, 'HH:mm');
  if (isToday(date)) return t('OUTSIDER_WHATSAPP_STATUS.TIME.TODAY', { time });
  if (isYesterday(date)) {
    return t('OUTSIDER_WHATSAPP_STATUS.TIME.YESTERDAY', { time });
  }
  return t('OUTSIDER_WHATSAPP_STATUS.TIME.DATE', {
    date: format(date, 'dd/MM/yyyy'),
    time,
  });
};

export const durationLabel = seconds =>
  `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

export const formatPhone = phone =>
  (phone && parsePhoneNumberFromString(phone)?.formatInternational()) || phone;

export const typeLabel = (t, type) => {
  switch (type) {
    case 'text':
      return t('OUTSIDER_WHATSAPP_STATUS.TYPES.TEXT');
    case 'image':
      return t('OUTSIDER_WHATSAPP_STATUS.TYPES.IMAGE');
    case 'video':
      return t('OUTSIDER_WHATSAPP_STATUS.TYPES.VIDEO');
    default:
      return t('OUTSIDER_WHATSAPP_STATUS.TYPES.AUDIO');
  }
};

export const situation = (t, status) => {
  if (status.deleted) {
    return {
      color: 'ruby',
      label: t('OUTSIDER_WHATSAPP_STATUS.SITUATION.DELETED'),
    };
  }
  if (isActive(status)) {
    return {
      color: 'teal',
      label: t('OUTSIDER_WHATSAPP_STATUS.SITUATION.ACTIVE', {
        hours: hoursLeft(status),
      }),
    };
  }
  return {
    color: 'slate',
    label: t('OUTSIDER_WHATSAPP_STATUS.SITUATION.EXPIRED'),
  };
};

export const errorMessage = (t, error) => {
  if (error?.response?.status === 401) {
    return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.NO_PERMISSION');
  }
  const { error: code, message } = error?.response?.data || {};
  switch (code) {
    case 'not_configured':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.NOT_CONFIGURED');
    case 'evolution_unauthorized':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.EVOLUTION_UNAUTHORIZED');
    case 'evolution_unreachable':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.EVOLUTION_UNREACHABLE');
    case 'evolution_timeout':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.EVOLUTION_TIMEOUT');
    case 'evolution_error':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.EVOLUTION_ERROR', { message });
    case 'empty_audience':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.EMPTY_AUDIENCE');
    case 'numbers_not_found':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.NUMBERS_NOT_FOUND', {
        numbers: message,
      });
    case 'unsupported_type':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.UNSUPPORTED_TYPE');
    default:
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.GENERIC');
  }
};

// números com DDD (o 55 é opcional), um por linha ou separados por vírgula. Espaços e
// traços dentro do número valem ("62 99999-8888"); números só separados por espaço também.
const MAX_DIGITS = 13;

export const parseNumbers = text => [
  ...new Set(
    text
      .split(/[,;\n]+/)
      .flatMap(chunk => {
        const digits = chunk.replace(/\D/g, '');
        return digits.length <= MAX_DIGITS
          ? [digits]
          : chunk.split(/\s+/).map(part => part.replace(/\D/g, ''));
      })
      .filter(number => number.length >= 10 && number.length <= MAX_DIGITS)
  ),
];

// audience: { mode: 'contacts' | 'selected' | 'numbers', contactIds, numbers }
export const emptyAudience = () => ({
  mode: 'contacts',
  contactIds: [],
  numbers: '',
});

export const isAudienceValid = audience => {
  if (audience.mode === 'selected') return audience.contactIds.length > 0;
  if (audience.mode === 'numbers') {
    return parseNumbers(audience.numbers).length > 0;
  }
  return true;
};

export const audienceParams = audience => {
  if (audience.mode === 'selected') {
    return { audience: 'selected', contact_ids: audience.contactIds };
  }
  if (audience.mode === 'numbers') {
    return { audience: 'numbers', numbers: parseNumbers(audience.numbers) };
  }
  return {};
};

export const appendAudience = (formData, audience) => {
  const params = audienceParams(audience);
  if (!params.audience) return;
  formData.append('audience', params.audience);
  (params.contact_ids || params.numbers).forEach(value =>
    formData.append(params.contact_ids ? 'contact_ids[]' : 'numbers[]', value)
  );
};

// status já vistos neste navegador (id => quando), como as bolinhas cinzas do WhatsApp
export const loadSeen = () => {
  const seen = LocalStorage.get(SEEN_STORE);
  return seen && typeof seen === 'object' ? seen : {};
};

export const saveSeen = seen => {
  const limit = nowInSeconds() - 2 * STATUS_LIFETIME;
  LocalStorage.set(
    SEEN_STORE,
    Object.fromEntries(Object.entries(seen).filter(([, at]) => at > limit))
  );
};

export const markSeen = (seen, id) => ({ ...seen, [id]: nowInSeconds() });

export const loadLayout = () =>
  LocalStorage.get(LAYOUT_STORE) === 'cards' ? 'cards' : 'list';

export const saveLayout = layout => LocalStorage.set(LAYOUT_STORE, layout);

// a aba dos contatos abre em grade, a não ser que a pessoa tenha escolhido a lista
export const loadContactsLayout = () =>
  LocalStorage.get(CONTACTS_LAYOUT_STORE) === 'list' ? 'list' : 'cards';

export const saveContactsLayout = layout =>
  LocalStorage.set(CONTACTS_LAYOUT_STORE, layout);

// a mídia vem da Evolution pelo nosso servidor; cada uma é baixada uma vez por visita à página
const mediaCache = new Map();

// as prévias da grade baixam no máximo 3 por vez, para não ocupar o servidor todo de uma vez
const PREVIEW_LIMIT = 3;
const previewQueue = [];
let previewsRunning = 0;

const queuePreview = task =>
  new Promise((resolve, reject) => {
    const run = () => {
      previewsRunning += 1;
      task()
        .then(resolve, reject)
        .finally(() => {
          previewsRunning -= 1;
          previewQueue.shift()?.();
        });
    };
    if (previewsRunning < PREVIEW_LIMIT) run();
    else previewQueue.push(run);
  });

export const fetchMedia = (inboxId, id, { preview = false } = {}) => {
  if (!mediaCache.has(id)) {
    const download = () => WhatsappStatusAPI.getMedia(inboxId, id);
    const request = (preview ? queuePreview(download) : download()).then(
      ({ data }) => ({ url: URL.createObjectURL(data), type: data.type })
    );
    request.catch(() => mediaCache.delete(id));
    mediaCache.set(id, request);
  }
  return mediaCache.get(id);
};

// na conversa: o status que o contato respondeu, ou null quando a mensagem citada não é um status
const repliedStatusCache = new Map();

export const fetchRepliedStatus = (inboxId, id) => {
  const key = `${inboxId}:${id}`;
  if (!repliedStatusCache.has(key)) {
    repliedStatusCache.set(
      key,
      WhatsappStatusAPI.getRepliedStatus(inboxId, id).then(
        ({ data }) => data,
        () => null
      )
    );
  }
  return repliedStatusCache.get(key);
};

export const clearMediaCache = () => {
  mediaCache.forEach(request =>
    request.then(
      ({ url }) => URL.revokeObjectURL(url),
      () => {}
    )
  );
  mediaCache.clear();
};

export const downloadMedia = async (inboxId, status) => {
  const { url, type } = await fetchMedia(inboxId, status.id);
  const extension = type.split('/')[1].split(';')[0].replace('jpeg', 'jpg');
  const link = document.createElement('a');
  link.href = url;
  link.download = `status-${format(fromUnixTime(status.timestamp), 'yyyy-MM-dd-HHmm')}.${extension}`;
  link.click();
};

const csvCell = value => `"${String(value).replace(/"/g, '""')}"`;

export const statusesCsv = (t, statuses) => {
  const header = [
    t('OUTSIDER_WHATSAPP_STATUS.CSV.PUBLISHED_AT'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.TYPE'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.TEXT'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.SITUATION'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.VIEWS'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.LIKES'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.REPLIES'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.WHO_LIKED'),
    t('OUTSIDER_WHATSAPP_STATUS.CSV.REPLY_TEXTS'),
  ];
  const rows = statuses.map(status => [
    format(fromUnixTime(status.timestamp), 'dd/MM/yyyy HH:mm'),
    typeLabel(t, status.type),
    status.text || '',
    situation(t, status).label,
    status.views ?? '',
    status.reactions.length,
    status.replies.length,
    status.reactions
      .map(reaction => `${reaction.name} ${reaction.emoji}`)
      .join(', '),
    status.replies.map(reply => `${reply.name}: ${reply.content}`).join(' | '),
  ]);
  // o BOM faz o Excel abrir os acentos certo; ";" é o separador do Excel em português
  return `\uFEFF${[header, ...rows].map(row => row.map(csvCell).join(';')).join('\r\n')}`;
};
