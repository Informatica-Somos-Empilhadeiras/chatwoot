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
  if (status === 404) return t('OUTSIDER_CRM.ERRORS.NOT_FOUND');
  return message || t('OUTSIDER_CRM.ERRORS.GENERIC');
};

// sem acento e sem maiúscula, para "andre" achar "André"
export const normalize = text =>
  (text || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
