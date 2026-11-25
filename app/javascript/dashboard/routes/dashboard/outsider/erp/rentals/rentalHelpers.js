// OUTSIDER: ajudas de exibição de Locação e máquinas (tabela, painel e bloco do contato): tipo de contrato, valor por
// período, "vence em N dias", nome da máquina e horímetro. Os dados vêm de /outsider/erp/records/(contracts|machines|
// rental_invoices) e de /outsider/erp/records/rentals (Outsider::Erp::Rentals).
import { titleCase } from '../records/recordsConfig';

const DAY = 86400000;
const brasiliaDay = value => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const text = date.toLocaleDateString('en-CA', {
    timeZone: 'America/Sao_Paulo',
  });
  return Math.floor(new Date(text).getTime() / DAY);
};

// dias de hoje até a data (negativo = já passou); null sem data
export const daysUntil = (value, now = new Date()) => {
  if (!value) return null;
  const then = brasiliaDay(value);
  return then === null ? null : then - brasiliaDay(now);
};

// "CONTRATO DE LOCAÇÃO" -> RENTAL; manutenção e prestação de serviço; outro texto fica como veio
export const contractType = value => {
  const text = String(value || '').toUpperCase();
  if (text.includes('LOCA')) return 'RENTAL';
  if (text.includes('MANUT')) return 'MAINTENANCE';
  if (text.includes('PRESTA') || text.includes('SERVI')) return 'SERVICE';
  return '';
};

export const contractTypeClass = value =>
  ({
    RENTAL: 'bg-n-blue-3 text-n-blue-11',
    MAINTENANCE: 'bg-n-iris-3 text-n-iris-11',
    SERVICE: 'bg-n-amber-3 text-n-amber-11',
  })[contractType(value)] || 'bg-n-alpha-2 text-n-slate-11';

export const contractTypeLabel = (t, value) => {
  const key = contractType(value);
  return key ? t(`OUTSIDER_ERP.RENTALS.TYPES.${key}`) : titleCase(value) || '—';
};

// MENSAL / SEMANAL / ANUAL -> chave de "por mês", "por semana", "por ano"
export const periodKey = value =>
  ({ MENSAL: 'PER_MONTH', SEMANAL: 'PER_WEEK', ANUAL: 'PER_YEAR' })[
    String(value || '')
      .trim()
      .toUpperCase()
  ] || '';

// contrato ativo perto do fim: { key: 'DUE_IN' | 'DUE_TODAY' | 'OVERDUE', days } (a tela troca a pílula de ATIVO)
export const contractDue = (row, now = new Date()) => {
  if (String(row?.status || '').toUpperCase() !== 'ATIVO') return null;
  const days = daysUntil(row.termino, now);
  if (days === null || days > 30) return null;
  if (days < 0) return { key: 'OVERDUE', days: -days };
  return { key: days === 0 ? 'DUE_TODAY' : 'DUE_IN', days };
};

export const machineName = row =>
  titleCase(row?.descricao || row?.modelo || '') ||
  (row?.maquina || row?.numero ? `#${row.maquina || row.numero}` : '');

// "18110" (série); sem série, o patrimônio; sem os dois, o número do cadastro
export const machineTag = row =>
  row?.serie || row?.patrimonio || `#${row?.maquina || row?.numero || ''}`;

// horímetro em texto do ERP ("3412", "3.412,5") -> "3.412 h"; texto que não é número fica como veio
export const hourMeter = value => {
  const text = String(value || '').trim();
  if (!text) return '';
  const number = Number(text.replace(/\./g, '').replace(',', '.'));
  return Number.isFinite(number)
    ? `${Math.round(number).toLocaleString('pt-BR')} h`
    : text;
};
