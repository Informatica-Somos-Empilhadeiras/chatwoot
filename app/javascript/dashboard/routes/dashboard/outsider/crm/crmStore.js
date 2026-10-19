// OUTSIDER: estado do CRM compartilhado pelas partes que aparecem fora da tela do CRM
// (aba na conversa, bloco no painel do contato e selo de valor na lista de conversas).
// Acesso e pipelines são buscados uma vez por conta; o resumo de cada contato fica em cache
// e é recarregado depois de qualquer alteração feita por essas telas.
import { reactive } from 'vue';
import store from 'dashboard/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import { DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER } from 'dashboard/composables/useUISettings';

export const OPEN_CRM_TAB_EVENT = 'outsider_crm_open_tab';

export const SIDEBAR_ITEM = 'outsider_crm';
const SIDEBAR_PLACED_KEY = 'outsider_crm_sidebar_placed';

const CHIP_BATCH_DELAY = 50;
const CHIP_BATCH_SIZE = 100;

const emptyAccess = () => ({ enabled: false, administrator: false, units: [] });

export const crmState = reactive({
  accountId: null,
  access: emptyAccess(),
  pipelines: [],
  lostReasons: [],
  summaries: {},
  chips: {},
  pendingCreate: null,
});

let contextPromise = null;
const summaryRequests = {};
let chipQueue = new Set();
let chipTimer = null;

const currentAccountId = () =>
  window.location.pathname.match(/\/accounts\/(\d+)/)?.[1] || null;

const resetForAccount = accountId => {
  crmState.accountId = accountId;
  crmState.access = emptyAccess();
  crmState.pipelines = [];
  crmState.lostReasons = [];
  crmState.summaries = {};
  crmState.chips = {};
  contextPromise = null;
};

// Uma vez por usuário: põe o bloco CRM logo abaixo das ações da conversa e aberto. Quem já tinha
// uma ordem salva receberia o bloco no fim da lista; depois disso a ordem é a que a pessoa arrastar.
const placeSidebarItem = () => {
  const settings = store.getters.getUISettings || {};
  if (settings[SIDEBAR_PLACED_KEY]) return;
  const order = (
    settings.conversation_sidebar_items_order || [
      ...DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER,
    ]
  ).filter(item => item.name !== SIDEBAR_ITEM);
  const actionsIndex = order.findIndex(
    item => item.name === 'conversation_actions'
  );
  order.splice(actionsIndex + 1, 0, { name: SIDEBAR_ITEM });
  store.dispatch('updateUISettings', {
    uiSettings: {
      ...settings,
      conversation_sidebar_items_order: order,
      is_outsider_crm_open: true,
      [SIDEBAR_PLACED_KEY]: true,
    },
  });
};

const fetchContext = async () => {
  try {
    const { data } = await CrmAPI.getAccess();
    crmState.access = data;
    if (!data.enabled) return;
    placeSidebarItem();
    const [pipelines, reasons] = await Promise.all([
      CrmAPI.getPipelines(),
      CrmAPI.getLostReasons(),
    ]);
    crmState.pipelines = pipelines.data;
    crmState.lostReasons = reasons.data;
  } catch {
    // sem CRM (erro de rede ou sem permissão): as telas simplesmente não aparecem
    crmState.access = emptyAccess();
  }
};

export const ensureCrmContext = () => {
  const accountId = currentAccountId();
  if (accountId !== crmState.accountId) resetForAccount(accountId);
  if (!contextPromise) contextPromise = fetchContext();
  return contextPromise;
};

// a tela do CRM chama depois de mudar configurações, para a conversa ver pipelines novos
export const invalidateCrmContext = () => {
  contextPromise = null;
};

export const summaryKey = (contactId, conversationId) =>
  `${contactId}-${conversationId || ''}`;

export const loadContactSummary = async (contactId, conversationId) => {
  if (!contactId) return null;
  await ensureCrmContext();
  if (!crmState.access.enabled) return null;
  const key = summaryKey(contactId, conversationId);
  if (!summaryRequests[key]) {
    summaryRequests[key] = CrmAPI.getContactSummary(contactId, conversationId)
      .then(({ data }) => {
        crmState.summaries[key] = data;
        return data;
      })
      .finally(() => {
        delete summaryRequests[key];
      });
  }
  return summaryRequests[key];
};

const flushChips = async () => {
  chipTimer = null;
  const ids = [...chipQueue];
  chipQueue = new Set();
  for (let i = 0; i < ids.length; i += CHIP_BATCH_SIZE) {
    const batch = ids.slice(i, i + CHIP_BATCH_SIZE);
    try {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await CrmAPI.getContactSummaries(batch);
      batch.forEach(id => {
        crmState.chips[id] = data[id] || null;
      });
    } catch {
      batch.forEach(id => {
        crmState.chips[id] = null;
      });
    }
  }
};

// o selo de cada card pede seu contato; os pedidos próximos viram uma chamada só
export const requestContactChip = async contactId => {
  if (!contactId) return;
  await ensureCrmContext();
  if (!crmState.access.enabled || contactId in crmState.chips) return;
  crmState.chips[contactId] = undefined;
  chipQueue.add(contactId);
  if (!chipTimer) chipTimer = setTimeout(flushChips, CHIP_BATCH_DELAY);
};

export const refreshContact = async contactId => {
  delete crmState.chips[contactId];
  requestContactChip(contactId);
  const keys = Object.keys(crmState.summaries).filter(key =>
    key.startsWith(`${contactId}-`)
  );
  await Promise.all(
    keys.map(key =>
      loadContactSummary(contactId, key.slice(String(contactId).length + 1))
    )
  );
};

export const findPipeline = id =>
  crmState.pipelines.find(pipeline => pipeline.id === id);

export const unitName = id =>
  crmState.access.units.find(unit => unit.id === id)?.name || '';
