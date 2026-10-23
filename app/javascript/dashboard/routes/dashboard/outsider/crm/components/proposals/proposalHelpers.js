// OUTSIDER: utilidades das propostas do CRM (situações, cores, contas dos itens e links).
import { CRM_ROUTE } from '../../sections';
import { centsToInput, normalize, parseMoney } from '../../helpers';

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

// valor bruto da linha em centavos (quantidade × valor), antes do desconto
export const itemGross = item => {
  const quantity = parseQuantity(item.quantity);
  const price = parseMoney(item.unit_price);
  if ([quantity, price].some(Number.isNaN)) return NaN;
  return Math.round(quantity * price * 100);
};

// desconto em % (Entrega 18): "5" ou "2,5" vira número entre 0 e 100; inválido vira NaN
export const parsePercent = text => {
  const value = String(text ?? '')
    .trim()
    .replace('%', '')
    .replace(',', '.');
  if (!value) return 0;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 && number <= 100 ? number : NaN;
};

// desconto em centavos a partir do percentual sobre o bruto da linha
export const percentDiscount = (item, percentText) => {
  const gross = itemGross(item);
  const percent = parsePercent(percentText);
  if ([gross, percent].some(Number.isNaN)) return NaN;
  return Math.round((gross * percent) / 100);
};

// quanto o desconto em R$ representa do bruto, com até 2 casas ("5" ou "2,5")
export const discountPercent = item => {
  const gross = itemGross(item);
  const discount = parseMoney(item.discount);
  if (!gross || Number.isNaN(gross) || !discount || Number.isNaN(discount)) {
    return null;
  }
  const value = Math.round(((discount * 100) / gross) * 10000) / 100;
  return String(value).replace('.', ',');
};

// item novo da proposta, ainda livre (sem produto do catálogo)
export const blankItem = () => ({
  id: null,
  product_id: '',
  description: '',
  quantity: '1',
  unit_price: '',
  discount: '',
  discount_mode: 'money',
  discount_percent: '',
  show_details: false,
  refresh_details: false,
  image_url: null,
});

// valor sugerido do item do catálogo para o tipo da proposta
export const catalogPrice = (product, kind) =>
  kind === 'rental' ? product.rental_price_cents : product.sale_price_cents;

// campos do item da proposta que vêm do catálogo: descrição, valor sugerido e características (máquina)
export const productItemFields = (product, kind) => ({
  product_id: product.id,
  description: product.name,
  unit_price: centsToInput(catalogPrice(product, kind)),
  show_details: product.kind === 'machine',
  image_url: product.image_url,
  refresh_details: true,
});

// linha "pagamento" das condições (ex.: "Pagamento com recurso próprio", "Condição de pagamento"),
// sem contar "Atraso de pagamento"; -1 quando não tem
export const paymentConditionIndex = conditions =>
  conditions.findIndex(condition => {
    const label = normalize(condition.label);
    return label.includes('pagamento') && !label.includes('atraso');
  });

// CNPJ com 14 caracteres, inclusive o alfanumérico (letras nas 12 primeiras posições)
export const lookupDocument = text => {
  const value = String(text || '')
    .toUpperCase()
    .replace(/[^0-9A-Z]/g, '');
  return /^[0-9A-Z]{12}[0-9]{2}$/.test(value) ? value : '';
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
