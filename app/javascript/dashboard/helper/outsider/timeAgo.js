// OUTSIDER: "há 5 minutos" no idioma da tela (o dynamicTime do Chatwoot escreve sempre em inglês)
const UNITS = [
  ['year', 31536000],
  ['month', 2592000],
  ['week', 604800],
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
];

export const timeAgo = (unixSeconds, locale = 'pt-BR') => {
  if (!unixSeconds) return '';
  const seconds = Math.round(unixSeconds - Date.now() / 1000);
  const format = new Intl.RelativeTimeFormat(String(locale).replace('_', '-'), {
    numeric: 'auto',
  });
  const unit = UNITS.find(([, size]) => Math.abs(seconds) >= size);
  if (!unit) return format.format(0, 'second');
  return format.format(Math.round(seconds / unit[1]), unit[0]);
};
