// OUTSIDER: o que a pessoa logada pode fazer com o ERP (Outsider::Erp, StatusesController) e ajudas de exibição
// das OS e orçamentos. O status é buscado uma vez por conta (OutsiderGlobal.vue) e de novo ao salvar as Configurações.
import { reactive } from 'vue';
import ErpAPI from 'dashboard/api/outsider/erp';

export const ERP_ROUTE = 'outsider_erp';

export const erpState = reactive({
  loaded: false,
  accountId: null,
  enabled: false,
  canEdit: false,
  writeEnabled: false,
  ordersEnabled: true,
  quotesEnabled: false,
  quoteWriteEnabled: false,
  canCreateQuote: false,
  // cadastrar cliente no ERP: gravação ligada nas Configurações + "Usa" no Cadastro de clientes do perfil
  canRegisterClient: false,
  administrator: false,
  fields: [],
  fieldKinds: {},
  companies: [],
  // { banco: nome na tela } (Configurações do ERP): "somosfilial" aparece como "Filial Distrito Federal"
  companyNames: {},
  lockedStatuses: [],
  // NF-e: o PDF da nota espelhado do Nextcloud (conexão nas Configurações)
  nextcloudInvoices: false,
  // fotos dos produtos (Nextcloud, pasta das fotos nas Configurações)
  productPhotos: false,
});

// o nome da unidade para as telas; sem nome nas Configurações, o próprio banco
export const companyName = db =>
  erpState.companyNames[String(db || '').toLowerCase()] || db || '';

export const loadErpStatus = async accountId => {
  if (!accountId) return;
  try {
    const { data } = await ErpAPI.status();
    Object.assign(erpState, {
      loaded: true,
      accountId,
      enabled: data.enabled,
      canEdit: data.can_edit,
      writeEnabled: data.write_enabled,
      // backend antigo não manda o campo: as OS continuam aparecendo
      ordersEnabled: data.orders_enabled !== false,
      quotesEnabled: data.quotes_enabled,
      quoteWriteEnabled: data.quote_write_enabled,
      canCreateQuote: data.can_create_quote,
      canRegisterClient: data.can_register_client === true,
      administrator: data.administrator,
      fields: data.fields || [],
      fieldKinds: data.field_kinds || {},
      companies: data.companies || [],
      companyNames: data.company_names || {},
      lockedStatuses: data.locked_statuses || [],
      nextcloudInvoices: data.nextcloud_invoices === true,
      productPhotos: data.product_photos === true,
    });
  } catch {
    // sem acesso pelo perfil (403) ou fora do ar: o ERP some da tela
    Object.assign(erpState, { loaded: true, accountId, enabled: false });
  }
};

// OS em status terminal (FECHADA/CANCELADA/PERDIDA): so leitura; reabrir e no desktop do ERP
export const isOrderLocked = order =>
  erpState.lockedStatuses.includes(
    String(order?.Situacao || '')
      .trim()
      .toUpperCase()
  );

// listas de apoio da edição da OS (situações, técnicos, tipos de atendimento). Buscadas uma vez por conta e
// compartilhadas entre os cartões (o backend já guarda em cache por alguns minutos); uma falha deixa tentar de novo.
export const erpLists = reactive({
  loaded: false,
  statuses: [],
  technicians: [],
  attendanceTypes: [],
});

let listsPromise = null;
export const loadErpLists = () => {
  if (erpLists.loaded) return Promise.resolve(erpLists);
  if (!listsPromise) {
    listsPromise = ErpAPI.lists()
      .then(({ data }) => {
        Object.assign(erpLists, {
          loaded: true,
          statuses: data.statuses || [],
          technicians: data.technicians || [],
          attendanceTypes: data.attendance_types || [],
        });
        return erpLists;
      })
      .catch(() => {
        listsPromise = null;
        return erpLists;
      });
  }
  return listsPromise;
};

// a cópia do ERP ainda está chegando (202): tenta de novo algumas vezes
export const withLoadingRetry = async (
  request,
  { tries = 6, wait = 2500 } = {}
) => {
  for (let attempt = 0; attempt < tries; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop
    const response = await request();
    if (response.status !== 202) return response;
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      setTimeout(resolve, wait);
    });
  }
  throw Object.assign(new Error('loading'), { code: 'loading' });
};

// título do bloco do ERP no contato/negócio: com as OS ocultas, fica só "orçamentos"
export const erpPanelTitle = t =>
  t(
    erpState.ordersEnabled
      ? 'OUTSIDER_ERP.CONTACT.PANEL_TITLE'
      : 'OUTSIDER_ERP.CONTACT.PANEL_TITLE_QUOTES'
  );

export const orderKey = order => `${order.Empresa}:${order.CodigoOS}`;

const PLAIN_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

// valor para <input type="date"> (AAAA-MM-DD) no dia de Brasília. Data já gravada pela tela vem como
// "2026-11-20" e fica como está (new Date leria meia-noite UTC = dia anterior em Brasília)
export const toDateInput = value => {
  if (!value) return '';
  if (PLAIN_DATE.test(value)) return value;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
};

export const formatDate = value => {
  if (!value) return '';
  const plain = PLAIN_DATE.exec(value);
  if (plain) return `${plain[3]}/${plain[2]}/${plain[1]}`;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  // o ERP manda a data à meia-noite de Brasília em UTC (03:00Z)
  return date.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
};

export const formatMoney = value =>
  Number(value || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });

// cor do cartão no ERP (Verde, Amarelo, Vermelho...) -> bolinha
const COLORS = {
  VERDE: 'bg-n-teal-9',
  AMARELO: 'bg-n-amber-9',
  VERMELHO: 'bg-n-ruby-9',
  AZUL: 'bg-n-blue-9',
};
export const dotClass = color =>
  COLORS[String(color || '').toUpperCase()] || 'bg-n-slate-8';

// substatus "2-AGENDADO (DF)" -> etapa 2 (para a cor da pílula)
export const substatusClass = value => {
  const text = String(value || '').toUpperCase();
  if (text.includes('CANCEL')) return 'bg-n-ruby-3 text-n-ruby-11';
  if (text.includes('CONCLU')) return 'bg-n-teal-3 text-n-teal-11';
  if (text.includes('AGENDADO')) return 'bg-n-blue-3 text-n-blue-11';
  if (text.includes('AGENDAR')) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

export const quoteClass = status => {
  const text = String(status || '').toUpperCase();
  if (text.includes('FECHAD')) return 'bg-n-teal-3 text-n-teal-11';
  if (text.includes('PERD') || text.includes('CANCEL'))
    return 'bg-n-ruby-3 text-n-ruby-11';
  if (text.includes('NEGOC')) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

export const erpErrorMessage = (t, error) => {
  // o código do servidor vem antes: o axios põe o dele em error.code (ERR_BAD_REQUEST) e escondia o motivo real
  const code = error?.response?.data?.error || error?.code;
  const known = {
    loading: 'LOADING',
    erp_unavailable: 'UNAVAILABLE',
    erp_disabled: 'DISABLED',
    no_companies: 'NO_COMPANIES',
    write_disabled: 'WRITE_DISABLED',
    quote_write_disabled: 'QUOTE_WRITE_DISABLED',
    client_write_disabled: 'CLIENT_WRITE_DISABLED',
    invalid: 'INVALID',
    os_not_found: 'OS_NOT_FOUND',
    invoice_not_in_nextcloud: 'INVOICE_NOT_IN_NEXTCLOUD',
    nextcloud_unavailable: 'NEXTCLOUD_UNAVAILABLE',
  };
  if (error?.response?.status === 403 && !known[code])
    return t('OUTSIDER_ERP.ERRORS.NO_PERMISSION');
  // Nextcloud: senha recusada e pasta não encontrada têm texto próprio; o resto mostra o motivo (HTTP 400, SocketError...)
  const nextcloud = {
    'HTTP 401': 'NEXTCLOUD_AUTH',
    'HTTP 404': 'NEXTCLOUD_FOLDER',
  };
  const reason = String(error?.response?.data?.message || '');
  if (code === 'nextcloud_unavailable' && nextcloud[reason])
    return t(`OUTSIDER_ERP.ERRORS.${nextcloud[reason]}`);
  const text = t(`OUTSIDER_ERP.ERRORS.${known[code] || 'GENERIC'}`);
  // o motivo curto ajuda a achar o problema: o do ERP (HTTP 403, Net::ReadTimeout...) ou o status do próprio Chatwoot
  const detail = ['erp_unavailable', 'nextcloud_unavailable'].includes(code)
    ? reason.slice(0, 80)
    : '';
  const status = !known[code] && error?.response?.status;
  if (detail) return `${text} (${detail})`;
  return status ? `${text} (HTTP ${status})` : text;
};
