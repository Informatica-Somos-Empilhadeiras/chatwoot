// OUTSIDER: utilidades do CRM (dinheiro, datas e mensagens de erro).

const money = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

export const formatMoney = cents => money.format((cents || 0) / 100);

const shortMoney = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  notation: 'compact',
  maximumFractionDigits: 1,
});

// "R$ 82,5 mil", para selos e abas
export const formatMoneyShort = cents => shortMoney.format((cents || 0) / 100);

// dias inteiros entre hoje e uma data "AAAA-MM-DD" (negativo = já passou)
export const daysUntil = date => {
  if (!date) return null;
  const today = new Date();
  today.setHours(12, 0, 0, 0);
  return Math.round((new Date(`${date}T12:00:00`) - today) / 86400000);
};

export const daysSince = timestamp =>
  timestamp
    ? Math.max(0, Math.floor((Date.now() - new Date(timestamp)) / 86400000))
    : null;

// "68.000,50" ou "68000.5" viram 68000.5; vazio vira 0
export const parseMoney = text => {
  const value = String(text ?? '').trim();
  if (!value) return 0;
  const normalized = value.includes(',')
    ? value.replace(/\./g, '').replace(',', '.')
    : value;
  const number = Number(normalized.replace(/[^\d.-]/g, ''));
  return Number.isFinite(number) ? number : NaN;
};

export const centsToInput = cents =>
  cents ? (cents / 100).toFixed(2).replace('.', ',') : '';

export const formatDate = date =>
  date ? new Date(`${date}T12:00:00`).toLocaleDateString('pt-BR') : '';

const timeFormat = new Intl.DateTimeFormat('pt-BR', {
  hour: '2-digit',
  minute: '2-digit',
});

const sameDay = (a, b) => a.toDateString() === b.toDateString();

// "Hoje 14:00", "Amanhã 09:30", "Ontem 18:00" ou "21/10 14:00" (com o ano se não for este)
export const formatDateTime = (timestamp, t) => {
  if (!timestamp) return '';
  const date = new Date(timestamp);
  const time = timeFormat.format(date);
  const today = new Date();
  const tomorrow = new Date();
  tomorrow.setDate(today.getDate() + 1);
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);
  if (sameDay(date, today)) return `${t('OUTSIDER_CRM.DATES.TODAY')} ${time}`;
  if (sameDay(date, tomorrow))
    return `${t('OUTSIDER_CRM.DATES.TOMORROW')} ${time}`;
  if (sameDay(date, yesterday))
    return `${t('OUTSIDER_CRM.DATES.YESTERDAY')} ${time}`;
  const options =
    date.getFullYear() === today.getFullYear()
      ? { day: '2-digit', month: '2-digit' }
      : { day: '2-digit', month: '2-digit', year: 'numeric' };
  return `${date.toLocaleDateString('pt-BR', options)} ${time}`;
};

// valores para <input type="date"> e <input type="time"> no fuso do navegador
export const toDateInput = date => {
  const pad = number => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
};

export const toTimeInput = date =>
  `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;

// junta data e hora digitadas num ISO com fuso; sem hora, vale o fim do expediente (18:00)
export const combineDateTime = (date, time) =>
  date ? new Date(`${date}T${time || '18:00'}:00`).toISOString() : null;

export const TASK_KINDS = [
  { value: 'todo', icon: 'i-lucide-square-check' },
  { value: 'call', icon: 'i-lucide-phone' },
  { value: 'meeting', icon: 'i-lucide-users' },
  { value: 'visit', icon: 'i-lucide-map-pin' },
  { value: 'proposal', icon: 'i-lucide-file-text' },
  { value: 'follow_up', icon: 'i-lucide-repeat' },
];

export const taskKindIcon = kind =>
  TASK_KINDS.find(item => item.value === kind)?.icon || 'i-lucide-square-check';

export const STATUS_COLORS = {
  open: 'bg-n-blue-3 text-n-blue-11',
  won: 'bg-n-teal-3 text-n-teal-11',
  lost: 'bg-n-ruby-3 text-n-ruby-11',
  forwarded: 'bg-n-amber-3 text-n-amber-11',
};

export const STAGE_COLORS = [
  '#3B82F6',
  '#10B981',
  '#8B5CF6',
  '#F59E0B',
  '#06B6D4',
  '#64748B',
];

export const errorMessage = (t, error) => {
  const status = error?.response?.status;
  const { error: code, message } = error?.response?.data || {};
  if (status === 401 || code === 'crm_forbidden' || code === 'crm_admin_only') {
    return t('OUTSIDER_CRM.ERRORS.NO_PERMISSION');
  }
  if (code === 'crm_access_denied') return t('OUTSIDER_CRM.ERRORS.NO_ACCESS');
  if (code === 'in_use') return message || t('OUTSIDER_CRM.ERRORS.IN_USE');
  // 404 sem JSON = o servidor não conhece a rota: atualização aplicada sem reiniciar o Rails
  if (status === 404 && typeof error?.response?.data !== 'object') {
    return t('OUTSIDER_CRM.ERRORS.SERVER_OUTDATED');
  }
  if (status === 404) return t('OUTSIDER_CRM.ERRORS.NOT_FOUND');
  return message || t('OUTSIDER_CRM.ERRORS.GENERIC');
};

// sem acento e sem maiúscula, para "andre" achar "André"
export const normalize = text =>
  (text || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
