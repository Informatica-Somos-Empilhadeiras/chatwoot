// OUTSIDER: contas de data da Agenda dos Aplicativos (dia, semana começando na segunda e mês em 6 semanas). As datas
// dos eventos chegam no fuso da pessoa, sem o "Z" (ex.: 2026-11-24T09:00:00.0000000), e são lidas como hora local.
const pad = n => String(n).padStart(2, '0');

export const dayKey = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

export const timeKey = date =>
  `${pad(date.getHours())}:${pad(date.getMinutes())}`;

export const localIso = date => `${dayKey(date)}T${timeKey(date)}:00`;

// "2026-11-24T09:00:00.0000000" -> Date local (sem converter fuso)
export const parseLocal = value => {
  const match = String(value || '').match(
    /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?/
  );
  if (!match) return new Date(NaN);
  const [, y, m, d, hh = '0', mm = '0'] = match;
  return new Date(Number(y), Number(m) - 1, Number(d), Number(hh), Number(mm));
};

export const addDays = (date, days) => {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
};

export const startOfDay = date => {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
};

// segunda-feira da semana
export const startOfWeek = date =>
  addDays(startOfDay(date), -((date.getDay() + 6) % 7));

// view: 'day' | 'week' | 'month' -> { from, to, days: Date[] } (o mês sempre em semanas inteiras)
export const rangeOf = (view, anchor) => {
  if (view === 'day') {
    const from = startOfDay(anchor);
    return { from, to: addDays(from, 1), days: [from] };
  }
  if (view === 'week') {
    const from = startOfWeek(anchor);
    return {
      from,
      to: addDays(from, 7),
      days: Array.from({ length: 7 }, (_, i) => addDays(from, i)),
    };
  }
  const first = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
  const from = startOfWeek(first);
  const last = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0);
  const weeks = Math.ceil((last - from) / (7 * 86400000) + 1 / 7);
  const count = Math.max(weeks, 5) * 7;
  return {
    from,
    to: addDays(from, count),
    days: Array.from({ length: count }, (_, i) => addDays(from, i)),
  };
};

export const shift = (view, anchor, step) => {
  if (view === 'day') return addDays(anchor, step);
  if (view === 'week') return addDays(anchor, step * 7);
  return new Date(anchor.getFullYear(), anchor.getMonth() + step, 1);
};

// o evento passa por este dia? (eventos de vários dias e de dia inteiro aparecem em todos os dias)
export const coversDay = (event, day) => {
  const start = parseLocal(event.start);
  const end = parseLocal(event.end);
  const dayStart = startOfDay(day);
  const dayEnd = addDays(dayStart, 1);
  if (+start === +end) return start >= dayStart && start < dayEnd;
  return start < dayEnd && end > dayStart;
};

// cor estável por assunto (as mesmas reuniões ficam sempre da mesma cor); dia inteiro fica cinza
export const colorOf = event => {
  if (event.all_day) return 'c5';
  const text = String(event.subject || '');
  let hash = 0;
  for (let i = 0; i < text.length; i += 1)
    hash = (hash * 31 + text.charCodeAt(i)) % 997;
  return `c${hash % 5}`;
};
