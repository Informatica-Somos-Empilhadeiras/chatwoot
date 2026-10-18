// OUTSIDER: funções da busca dentro da conversa e dos separadores de dia.
// Datas das mensagens vêm em segundos (created_at do Chatwoot) e os dias são
// sempre no fuso de quem está olhando.

import { splitSenderHeader } from './mediaAlbum';

export const MIN_TERM_LENGTH = 2; // igual ao Outsider::ConversationHistory
const MAX_TERMS = 8;
const COMBINING_MARKS = /[̀-ͯ]/g;

const foldChar = char =>
  char.normalize('NFD').replace(COMBINING_MARKS, '').toLowerCase();

// texto sem acento e minúsculo, com o índice de cada letra no texto original
const foldWithIndex = text => {
  let folded = '';
  const index = [];
  Array.from(text || '').reduce((position, char) => {
    const plain = foldChar(char);
    folded += plain;
    for (let i = 0; i < plain.length; i += 1) index.push(position);
    return position + char.length;
  }, 0);
  index.push((text || '').length);
  return { folded, index };
};

export const normalizeText = text => foldWithIndex(text).folded;

export const searchTerms = query =>
  [
    ...new Set(
      normalizeText(query)
        .split(/\s+/)
        .filter(term => Array.from(term).length >= MIN_TERM_LENGTH)
    ),
  ].slice(0, MAX_TERMS);

// trechos [início, fim) do texto original onde aparece alguma das palavras
export const findMatches = (text, terms) => {
  if (!text || !terms?.length) return [];
  const { folded, index } = foldWithIndex(text);
  const ranges = [];
  terms.forEach(term => {
    let at = folded.indexOf(term);
    while (at !== -1) {
      ranges.push([index[at], index[at + term.length]]);
      at = folded.indexOf(term, at + term.length);
    }
  });
  ranges.sort((a, b) => a[0] - b[0]);
  return ranges.reduce((merged, range) => {
    const last = merged[merged.length - 1];
    if (last && range[0] <= last[1]) last[1] = Math.max(last[1], range[1]);
    else merged.push([...range]);
    return merged;
  }, []);
};

// pedaço da mensagem em volta da primeira palavra encontrada, já separado em
// partes com e sem destaque (com "…" onde foi cortado); nos grupos tira o
// "**+55 ... - Nome:**" do começo e devolve à parte em `header`
export const buildSnippet = (content, terms, radius = 70) => {
  const { header, body } = splitSenderHeader(content || '');
  const text = body.replace(/\s+/g, ' ');
  const matches = findMatches(text, terms);
  const center = matches.length ? matches[0][0] : 0;
  let start = Math.max(0, center - radius);
  let end = Math.min(text.length, center + radius * 2);
  // corta nos espaços para não partir palavras
  const spaceAfterStart = text.indexOf(' ', start);
  if (start > 0 && spaceAfterStart !== -1 && spaceAfterStart < center) {
    start = spaceAfterStart + 1;
  }
  const spaceBeforeEnd = text.lastIndexOf(' ', end);
  if (end < text.length && spaceBeforeEnd > center) end = spaceBeforeEnd;

  const parts = [];
  let cursor = start;
  matches
    .filter(([from, to]) => to > start && from < end)
    .forEach(([from, to]) => {
      const hitStart = Math.max(from, start);
      const hitEnd = Math.min(to, end);
      if (hitStart > cursor) {
        parts.push({ text: text.slice(cursor, hitStart), hit: false });
      }
      parts.push({ text: text.slice(hitStart, hitEnd), hit: true });
      cursor = hitEnd;
    });
  if (cursor < end) parts.push({ text: text.slice(cursor, end), hit: false });

  if (start > 0) parts.unshift({ text: '… ', hit: false });
  if (end < text.length) parts.push({ text: ' …', hit: false });
  return { header, parts };
};

const pad = number => String(number).padStart(2, '0');

export const dateKeyOf = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

export const dayKeyOfUnix = unix => dateKeyOf(new Date(unix * 1000));

export const dateFromKey = key => {
  const [year, month, day] = key.split('-').map(Number);
  return new Date(year, month - 1, day);
};

// segundos do início do dia (ou da hora "HH:MM" informada) no fuso local
export const unixFromKey = (key, time = '') => {
  const date = dateFromKey(key);
  if (time) {
    const [hours, minutes] = time.split(':').map(Number);
    date.setHours(hours, minutes, 0, 0);
  }
  return Math.floor(date.getTime() / 1000);
};

export const shiftKey = (key, days) => {
  const [year, month, day] = key.split('-').map(Number);
  return dateKeyOf(new Date(year, month - 1, day + days));
};

export const unixEndOfKey = key => unixFromKey(shiftKey(key, 1));

// id da primeira mensagem de cada dia -> "AAAA-MM-DD" (lista já com álbuns);
// uma mensagem fora de ordem (mais antiga no fim) não cria um dia repetido
export const dayStarts = messages => {
  const starts = new Map();
  let latestKey = '';
  messages.forEach(message => {
    const key = dayKeyOfUnix(message.createdAt);
    if (key > latestKey) {
      starts.set(message.id, key);
      latestKey = key;
    }
  });
  return starts;
};

export const toLocaleTag = locale => (locale || 'pt-BR').replace('_', '-');

const capitalize = text => text.charAt(0).toUpperCase() + text.slice(1);

const formatters = new Map();
const formatterFor = (locale, options) => {
  const key = `${locale}|${JSON.stringify(options)}`;
  if (!formatters.has(key)) {
    formatters.set(key, new Intl.DateTimeFormat(locale, options));
  }
  return formatters.get(key);
};

export const formatDate = (date, locale, options) =>
  formatterFor(toLocaleTag(locale), options).format(date);

/**
 * Nome do dia para o separador: "Hoje", "Ontem" ou "Quinta-feira" e a data.
 * labels: { today, yesterday }
 */
export const dayLabel = (dateKey, locale, labels, now = new Date()) => {
  const date = dateFromKey(dateKey);
  const todayKey = dateKeyOf(now);
  const sameYear = date.getFullYear() === now.getFullYear();
  const fullDate = formatDate(date, locale, {
    day: 'numeric',
    month: 'long',
    ...(sameYear ? {} : { year: 'numeric' }),
  });
  const weekday = capitalize(formatDate(date, locale, { weekday: 'long' }));

  if (dateKey === todayKey) {
    return { title: labels.today, subtitle: `${weekday}, ${fullDate}` };
  }
  if (dateKey === shiftKey(todayKey, -1)) {
    return { title: labels.yesterday, subtitle: `${weekday}, ${fullDate}` };
  }
  return { title: weekday, subtitle: fullDate };
};

export const isServerMessageId = id => Number.isInteger(id);

export const firstServerId = messages =>
  messages.find(message => isServerMessageId(message.id))?.id || 0;

export const lastServerId = messages =>
  messages.findLast(message => isServerMessageId(message.id))?.id || 0;

const byTimeThenId = (a, b) => {
  if (a.created_at !== b.created_at) return a.created_at - b.created_at;
  if (!isServerMessageId(a.id)) return 1;
  if (!isServerMessageId(b.id)) return -1;
  return a.id - b.id;
};

/**
 * Junta listas de mensagens (formato da API) sem repetir, em ordem de envio.
 * Se a mesma mensagem vier em mais de uma lista, fica a da última lista.
 * Mensagem ainda enviando some quando a versão do servidor (echo_id) chega.
 */
export const mergeMessages = (...lists) => {
  const byId = new Map();
  lists.flat().forEach(message => byId.set(message.id, message));
  // só a versão do servidor substitui a que está enviando (que tem id === echo_id)
  const echoIds = new Set(
    [...byId.values()]
      .filter(message => isServerMessageId(message.id))
      .map(message => message.echo_id)
      .filter(Boolean)
  );
  return [...byId.values()]
    .filter(
      message => isServerMessageId(message.id) || !echoIds.has(message.id)
    )
    .sort(byTimeThenId);
};

// semanas do mês (domingo a sábado) com as datas em "AAAA-MM-DD"
export const monthGrid = monthKey => {
  const [year, month] = monthKey.split('-').map(Number);
  const first = new Date(year, month - 1, 1);
  const start = new Date(first);
  start.setDate(1 - first.getDay());
  const weeks = [];
  const cursor = new Date(start);
  do {
    const week = [];
    for (let i = 0; i < 7; i += 1) {
      week.push({
        key: dateKeyOf(cursor),
        day: cursor.getDate(),
        inMonth: cursor.getMonth() === month - 1,
      });
      cursor.setDate(cursor.getDate() + 1);
    }
    weeks.push(week);
  } while (cursor.getMonth() === month - 1);
  return weeks;
};

export const shiftMonth = (monthKey, months) => {
  const [year, month] = monthKey.split('-').map(Number);
  const date = new Date(year, month - 1 + months, 1);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}`;
};
