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
    case 'unsupported_type':
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.UNSUPPORTED_TYPE');
    default:
      return t('OUTSIDER_WHATSAPP_STATUS.ERRORS.GENERIC');
  }
};

// números com DDI e DDD, separados por vírgula, espaço ou linha
export const parseNumbers = text => [
  ...new Set(
    text
      .split(/[\s,;]+/)
      .map(number => number.replace(/\D/g, ''))
      .filter(number => number.length >= 10)
  ),
];

export const appendAudience = (formData, audience) => {
  if (audience.mode !== 'numbers') return;
  formData.append('audience', 'numbers');
  parseNumbers(audience.numbers).forEach(number =>
    formData.append('numbers[]', number)
  );
};

export const audienceParams = audience =>
  audience.mode === 'numbers'
    ? { audience: 'numbers', numbers: parseNumbers(audience.numbers) }
    : {};

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

// a mídia vem da Evolution pelo nosso servidor; cada uma é baixada uma vez por visita à página
const mediaCache = new Map();

export const fetchMedia = (inboxId, id) => {
  if (!mediaCache.has(id)) {
    const request = WhatsappStatusAPI.getMedia(inboxId, id).then(
      ({ data }) => ({ url: URL.createObjectURL(data), type: data.type })
    );
    request.catch(() => mediaCache.delete(id));
    mediaCache.set(id, request);
  }
  return mediaCache.get(id);
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
