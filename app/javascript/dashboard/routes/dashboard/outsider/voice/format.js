// OUTSIDER: números e tempos do telefone na tela (Entrega 22): "(62) 99999-8888", "0800 123 4567", "3:07".
export const formatPhone = value => {
  let digits = String(value || '').replace(/\D/g, '');
  if (digits.length <= 4) return digits;
  if (/^(0800|0300)\d{7}$/.test(digits)) {
    return `${digits.slice(0, 4)} ${digits.slice(4, 7)} ${digits.slice(7)}`;
  }
  if ([12, 13].includes(digits.length) && digits.startsWith('55')) {
    digits = digits.slice(2);
  }
  if ([11, 12].includes(digits.length) && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  if (digits.length === 11) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
  }
  if (digits.length === 10) {
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  }
  if (digits.length === 8) return `${digits.slice(0, 4)}-${digits.slice(4)}`;
  return digits;
};

export const formatDuration = totalSeconds => {
  const seconds = Math.max(0, Math.round(totalSeconds || 0));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const rest = String(seconds % 60).padStart(2, '0');
  if (hours) return `${hours}:${String(minutes).padStart(2, '0')}:${rest}`;
  return `${minutes}:${rest}`;
};

// tempo somado do mês: "11 h 39 min" ou "45 min"
export const formatTalkTime = totalSeconds => {
  const minutes = Math.round((totalSeconds || 0) / 60);
  const hours = Math.floor(minutes / 60);
  return hours ? `${hours} h ${minutes % 60} min` : `${minutes} min`;
};

// taxa do painel (Entrega 24): "86,1%" ou "—" sem ligação para medir
export const formatPercent = value =>
  value === null || value === undefined
    ? '—'
    : `${String(value).replace('.', ',')}%`;

const WEEKDAYS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const MONTHS = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

// data "2026-10-06" do painel (já no fuso da telefonia): 06/10/2026, 06/10 (day), "ter 06/10" (weekday) ou
// out/26 (month)
export const formatDate = (value, style = 'full') => {
  const [year, month, day] = String(value).split('-').map(Number);
  const pad = number => String(number).padStart(2, '0');
  if (style === 'month') return `${MONTHS[month - 1]}/${String(year).slice(2)}`;
  if (style === 'day') return `${pad(day)}/${pad(month)}`;
  if (style === 'weekday') {
    const weekday = new Date(year, month - 1, day).getDay();
    return `${WEEKDAYS[weekday]} ${pad(day)}/${pad(month)}`;
  }
  return `${pad(day)}/${pad(month)}/${year}`;
};

// arquivo que veio do servidor (relatório em PDF, planilhas): baixa com o nome que ele mandou
export const downloadBlob = ({ data, headers }) => {
  const disposition = headers?.['content-disposition'] || '';
  const name =
    decodeURIComponent(
      (disposition.match(/filename\*=UTF-8''([^;]+)/) || [])[1] || ''
    ) ||
    (disposition.match(/filename="?([^";]+)"?/) || [])[1] ||
    'relatorio';
  const url = URL.createObjectURL(data);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
