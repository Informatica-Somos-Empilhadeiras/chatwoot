// OUTSIDER: hora da lista de conversas como no WhatsApp: "13:59" hoje, "Ontem", o dia da semana
// nos últimos 7 dias e a data depois disso.
const DAY = 86400000;

const startOfDay = date => {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  return copy.getTime();
};

export const chatListTime = (
  unixSeconds,
  { locale = 'pt-BR', yesterday = 'Ontem', now = Date.now() } = {}
) => {
  if (!unixSeconds) return '';
  const lang = String(locale).replace('_', '-');
  const date = new Date(unixSeconds * 1000);
  const days = Math.round((startOfDay(now) - startOfDay(date)) / DAY);
  if (days <= 0) {
    return date.toLocaleTimeString(lang, {
      hour: '2-digit',
      minute: '2-digit',
    });
  }
  if (days === 1) return yesterday;
  if (days < 7) {
    const weekday = date.toLocaleDateString(lang, { weekday: 'long' });
    return (
      weekday.charAt(0).toUpperCase() + weekday.slice(1).replace(/-feira$/, '')
    );
  }
  return date.toLocaleDateString(lang, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
};
