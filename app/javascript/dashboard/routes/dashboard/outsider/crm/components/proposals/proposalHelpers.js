// OUTSIDER: utilidades das propostas do CRM (situações, cores, contas dos itens e links).
import { CRM_ROUTE } from '../../sections';
import { parseMoney } from '../../helpers';

// "vencida" não é gravada: rascunho ou enviada com a validade passada (display_status)
export const PROPOSAL_STATUSES = [
  'draft',
  'sent',
  'accepted',
  'rejected',
  'expired',
  'canceled',
];

export const PROPOSAL_STATUS_COLORS = {
  draft: 'bg-n-alpha-2 text-n-slate-11',
  sent: 'bg-n-blue-3 text-n-blue-11',
  accepted: 'bg-n-teal-3 text-n-teal-11',
  rejected: 'bg-n-ruby-3 text-n-ruby-11',
  expired: 'bg-n-amber-3 text-n-amber-11',
  canceled: 'bg-n-alpha-2 text-n-slate-10 line-through',
};

export const CUSTOMER_FIELDS = [
  { key: 'company', wide: true },
  { key: 'document' },
  { key: 'state_registration' },
  { key: 'address', wide: true },
  { key: 'district' },
  { key: 'city' },
  { key: 'state' },
  { key: 'zip' },
  { key: 'phone' },
  { key: 'email' },
  { key: 'attention', wide: true },
];

// quantidade "1,5" ou "2" vira número; vazio vira 1
export const parseQuantity = text => {
  const value = String(text ?? '')
    .trim()
    .replace(',', '.');
  if (!value) return 1;
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : NaN;
};

export const quantityToInput = quantity =>
  String(quantity ?? 1).replace('.', ',');

// total da linha em centavos (quantidade × valor − desconto), como o servidor calcula
export const itemTotal = item => {
  const quantity = parseQuantity(item.quantity);
  const price = parseMoney(item.unit_price);
  const discount = parseMoney(item.discount);
  if ([quantity, price, discount].some(Number.isNaN)) return NaN;
  return Math.round(quantity * price * 100) - Math.round(discount * 100);
};

export const proposalRoute = (accountScopedRoute, query) =>
  accountScopedRoute(CRM_ROUTE, { tab: 'proposals' }, query);

// nome do arquivo que o servidor manda no Content-Disposition (filename*=UTF-8''...)
export const pdfFilename = (headers, fallback) => {
  const header = headers?.['content-disposition'] || '';
  const encoded = header.match(/filename\*=UTF-8''([^;]+)/i);
  if (encoded) return decodeURIComponent(encoded[1]);
  const plain = header.match(/filename="?([^";]+)"?/i);
  return plain ? plain[1] : fallback;
};
