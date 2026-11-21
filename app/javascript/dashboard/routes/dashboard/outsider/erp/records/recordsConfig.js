// OUTSIDER: o que muda entre as listas da seção ERP (orçamentos, OS, pedidos e notas): aba da rota, rótulos, quem é a pessoa da
// linha (vendedor ou técnico) e as ajudas de exibição (pílula de status, data relativa, período). Os dados vêm de
// /outsider/erp/records/:kind (Outsider::Erp::Records::Lister), com todo o histórico do ERP.

export const KINDS = {
  quotes: { tab: 'orcamentos', key: 'QUOTES', icon: 'i-lucide-file-text' },
  orders: { tab: 'os', key: 'ORDERS', icon: 'i-lucide-wrench' },
  sales: { tab: 'pedidos', key: 'SALES', icon: 'i-lucide-shopping-cart' },
  // a aba Notas mostra uma das duas (Produtos | Serviços)
  invoices: { tab: 'notas', key: 'INVOICES', icon: 'i-lucide-receipt-text' },
  service_invoices: {
    tab: 'notas',
    key: 'SERVICE_INVOICES',
    icon: 'i-lucide-receipt',
  },
};

// tela do perfil de acesso de cada tipo (nós da corrente e abas)
export const SCREENS = {
  quotes: 'erp_quotes',
  orders: 'erp_orders',
  sales: 'erp_sales',
  invoices: 'erp_invoices',
  service_invoices: 'erp_invoices',
};

// número que a pessoa reconhece: a NFS-e mostra o da prefeitura (ou o RPS); sem ele, a sequência interna
export const displayNumber = record =>
  record.rotulo ||
  (record.kind === 'service_invoices'
    ? `#${record.numero ?? record.number}`
    : (record.numero ?? record.number));

export const kindForTab = tab =>
  Object.keys(KINDS).find(kind => KINDS[kind].tab === tab) || null;

// "empresa:numero" na rota (?open=) abre o painel de detalhe direto (links da corrente orçamento -> OS -> pedido)
export const recordKey = row => `${row.banco || row.company}:${row.numero}`;
export const parseKey = value => {
  const [company, number] = String(value || '').split(':');
  return company && Number(number) > 0
    ? { company, number: Number(number) }
    : null;
};

export const PER_PAGE = [25, 50, 100];

// presets do período (de/até em AAAA-MM-DD no dia de Brasília); "custom" abre as duas datas
const iso = date =>
  date.toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
export const PERIODS = [
  'all',
  'month',
  '30',
  '90',
  'year',
  'last_year',
  'custom',
];
export const periodRange = key => {
  const today = new Date();
  const year = today.getFullYear();
  const back = days => iso(new Date(today.getTime() - days * 86400000));
  switch (key) {
    case 'month':
      return { from: iso(new Date(year, today.getMonth(), 1)), to: iso(today) };
    case '30':
      return { from: back(30), to: iso(today) };
    case '90':
      return { from: back(90), to: iso(today) };
    case 'year':
      return { from: `${year}-01-01`, to: iso(today) };
    case 'last_year':
      return { from: `${year - 1}-01-01`, to: `${year - 1}-12-31` };
    default:
      return { from: '', to: '' };
  }
};

// cores das situações (orçamento, OS, pedido e notas)
export const statusClass = status => {
  const text = String(status || '').toUpperCase();
  if (!text) return 'bg-n-alpha-2 text-n-slate-11';
  if (
    text.includes('FATURAD') ||
    text.includes('ENVIAD') ||
    text.includes('AGUARD')
  )
    return 'bg-n-blue-3 text-n-blue-11';
  if (
    ['FECHAD', 'FINALIZ', 'IMPRESS', 'ATIVA'].some(word => text.includes(word))
  )
    return 'bg-n-teal-3 text-n-teal-11';
  if (['PERD', 'CANCEL', 'ERRO', 'INUTILIZ'].some(word => text.includes(word)))
    return 'bg-n-ruby-3 text-n-ruby-11';
  if (['NEGOC', 'ABERT', 'PAUSAD'].some(word => text.includes(word)))
    return 'bg-n-amber-3 text-n-amber-11';
  if (text.includes('RETIRAD')) return 'bg-n-iris-3 text-n-iris-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

// "hoje", "ontem", "há 3 dias", "amanhã", "em 4 dias" (o ERP manda a data em UTC; o dia é o de Brasília)
const dayNumber = value => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return Math.floor(new Date(iso(date)).getTime() / 86400000);
};
export const relativeDay = (t, value) => {
  const then = dayNumber(value);
  if (then === null) return '';
  const diff = dayNumber(new Date()) - then;
  if (diff === 0) return t('OUTSIDER_ERP.RECORDS.TODAY');
  if (diff === 1) return t('OUTSIDER_ERP.RECORDS.YESTERDAY');
  if (diff > 1 && diff < 60)
    return t('OUTSIDER_ERP.RECORDS.DAYS_AGO', { n: diff });
  if (diff === -1) return t('OUTSIDER_ERP.RECORDS.TOMORROW');
  if (diff < -1 && diff > -60)
    return t('OUTSIDER_ERP.RECORDS.IN_DAYS', { n: -diff });
  return '';
};

export const isLate = value => {
  const then = dayNumber(value);
  return then !== null && then < dayNumber(new Date());
};

// "LUCAS FERREIRA RORIZ" -> "Lucas Roriz"; "PRIMA FOODS SA" fica como está, só sem caixa alta gritante
export const titleCase = value =>
  String(value || '')
    .toLowerCase()
    .replace(
      /(^|[\s/(-])(\p{L})/gu,
      (_, sep, letter) => sep + letter.toUpperCase()
    )
    .replace(/\b(Ltda|Sa|S\.a\.?|Me|Epp|Eireli)\b/g, word =>
      word.toUpperCase()
    );

export const shortName = value => {
  const words = titleCase(value).split(/\s+/).filter(Boolean);
  return words.length > 1
    ? `${words[0]} ${words[words.length - 1]}`
    : words[0] || '';
};

export const initials = value =>
  shortName(value)
    .split(' ')
    .map(word => word[0])
    .join('')
    .toUpperCase();

export const place = row => [row.cidade, row.uf].filter(Boolean).join('/');
