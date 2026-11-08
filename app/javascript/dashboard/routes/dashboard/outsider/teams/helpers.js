// OUTSIDER: datas, nomes e textos da área Teams.
const pad = n => String(n).padStart(2, '0');

const sameDay = (a, b) =>
  a.getFullYear() === b.getFullYear() &&
  a.getMonth() === b.getMonth() &&
  a.getDate() === b.getDate();

export const timeOf = iso => {
  if (!iso) return '';
  const date = new Date(iso);
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

// lista: hora se for hoje, "Ontem", dia da semana nesta semana, senão dd/mm
export const listTime = (iso, t, locale = 'pt-BR') => {
  if (!iso) return '';
  const date = new Date(iso);
  const now = new Date();
  if (sameDay(date, now)) return timeOf(iso);
  const yesterday = new Date();
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(date, yesterday)) return t('OUTSIDER_TEAMS_AREA.YESTERDAY');
  if (now - date < 6 * 24 * 3600 * 1000) {
    const day = date.toLocaleDateString(locale, { weekday: 'short' });
    return day.replace('.', '').replace(/^\w/, c => c.toUpperCase());
  }
  return `${pad(date.getDate())}/${pad(date.getMonth() + 1)}`;
};

// separador de dia: "Hoje", "Ontem" ou "sábado, 8 de novembro"
export const dayLabel = (iso, t, locale = 'pt-BR') => {
  const date = new Date(iso);
  const now = new Date();
  const yesterday = new Date();
  yesterday.setDate(now.getDate() - 1);
  const full = date.toLocaleDateString(locale, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  });
  if (sameDay(date, now))
    return { title: t('OUTSIDER_TEAMS_AREA.TODAY'), full };
  if (sameDay(date, yesterday))
    return { title: t('OUTSIDER_TEAMS_AREA.YESTERDAY'), full };
  return { title: '', full };
};

export const dayKey = iso => {
  const date = new Date(iso);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
};

export const isImage = file => (file?.content_type || '').startsWith('image/');

export const errorText = (error, t) => {
  const code = error?.response?.data?.error;
  const known = [
    'not_connected',
    'not_configured',
    'file_too_big',
    'empty',
    'state',
    'already_linked',
    'forbidden',
    'reply_to',
    'resend',
    'upload_failed',
    'not_found',
  ];
  if (known.includes(code)) {
    const name = (error.response.data.message || '')
      .split(':')
      .slice(1)
      .join(':')
      .trim();
    return t(`OUTSIDER_TEAMS_AREA.ERRORS.${code.toUpperCase()}`, { name });
  }
  return (
    error?.response?.data?.message || t('OUTSIDER_TEAMS_AREA.ERRORS.GENERIC')
  );
};

// "há 3 min", "há 2 h", "há 4 dias" (lista de quem está conectado)
export const agoText = (iso, t) => {
  if (!iso) return '';
  const minutes = Math.max(0, Math.round((Date.now() - new Date(iso)) / 60000));
  if (minutes < 1) return t('OUTSIDER_TEAMS_GRAPH.AGO_NOW');
  if (minutes < 60) return t('OUTSIDER_TEAMS_GRAPH.AGO_MIN', { n: minutes });
  const hours = Math.round(minutes / 60);
  if (hours < 24) return t('OUTSIDER_TEAMS_GRAPH.AGO_HOURS', { n: hours });
  const days = Math.round(hours / 24);
  return t('OUTSIDER_TEAMS_GRAPH.AGO_DAYS', { n: days }, days);
};
