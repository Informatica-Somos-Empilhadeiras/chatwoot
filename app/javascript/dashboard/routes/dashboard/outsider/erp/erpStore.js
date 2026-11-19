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
  quotesEnabled: false,
  administrator: false,
  fields: [],
  companies: [],
});

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
      quotesEnabled: data.quotes_enabled,
      administrator: data.administrator,
      fields: data.fields || [],
      companies: data.companies || [],
    });
  } catch {
    // sem acesso pelo perfil (403) ou fora do ar: o ERP some da tela
    Object.assign(erpState, { loaded: true, accountId, enabled: false });
  }
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

export const orderKey = order => `${order.Empresa}:${order.CodigoOS}`;

export const formatDate = value => {
  if (!value) return '';
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
  const code = error?.code || error?.response?.data?.error;
  const known = {
    loading: 'LOADING',
    erp_unavailable: 'UNAVAILABLE',
    erp_disabled: 'DISABLED',
    write_disabled: 'WRITE_DISABLED',
    invalid: 'INVALID',
  };
  if (error?.response?.status === 403 && !known[code])
    return t('OUTSIDER_ERP.ERRORS.NO_PERMISSION');
  return t(`OUTSIDER_ERP.ERRORS.${known[code] || 'GENERIC'}`);
};
