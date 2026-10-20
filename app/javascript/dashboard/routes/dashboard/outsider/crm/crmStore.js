// OUTSIDER: estado do CRM compartilhado pelas partes que aparecem fora da tela do CRM
// (aba na conversa, bloco no painel do contato e selo de valor na lista de conversas).
// Acesso e pipelines são buscados uma vez por conta; o resumo de cada contato fica em cache
// e é recarregado depois de qualquer alteração feita por essas telas.
import { reactive } from 'vue';
import store from 'dashboard/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER } from 'dashboard/composables/useUISettings';
import { onCrmChange, startLiveUpdates } from './live';

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
  // "Nota interna CRM" na caixa de resposta: o editor da conversa vira o de nota do CRM
  noteMode: false,
  // sobe a cada mudança feita fora da aba (nota, tarefa) para a linha do tempo recarregar
  activityVersion: {},
  unitMembers: {},
  myTasks: { pending: 0, overdue: 0 },
  // histórico multiempresa por contato (jornadas, negócios em todas as unidades e encaminhamentos)
  histories: {},
  // negócios recebidos por encaminhamento que o usuário ainda não abriu (aviso e bolinha vermelha)
  received: [],
});

let contextPromise = null;
const summaryRequests = {};
const historyRequests = {};
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
  crmState.noteMode = false;
  crmState.activityVersion = {};
  crmState.unitMembers = {};
  crmState.myTasks = { pending: 0, overdue: 0 };
  crmState.histories = {};
  crmState.received = [];
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
    startLiveUpdates(crmState.accountId);
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

export const loadContactHistory = async contactId => {
  if (!contactId) return null;
  await ensureCrmContext();
  if (!crmState.access.enabled) return null;
  if (!historyRequests[contactId]) {
    historyRequests[contactId] = CrmAPI.getContactHistory(contactId)
      .then(({ data }) => {
        crmState.histories[contactId] = data;
        return data;
      })
      .finally(() => {
        delete historyRequests[contactId];
      });
  }
  return historyRequests[contactId];
};

export const refreshContact = async contactId => {
  delete crmState.chips[contactId];
  requestContactChip(contactId);
  if (crmState.histories[contactId]) {
    loadContactHistory(contactId).catch(() => {});
  }
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

export const bumpActivity = opportunityId => {
  crmState.activityVersion[opportunityId] =
    (crmState.activityVersion[opportunityId] || 0) + 1;
};

// membros da unidade, para escolher o responsável da tarefa (só gestor e administrador escolhem)
export const loadUnitMembers = async unitId => {
  if (!crmState.unitMembers[unitId]) {
    const { data } = await CrmAPI.getUnit(unitId);
    crmState.unitMembers[unitId] = (data.members || []).map(member => ({
      id: member.user_id,
      name: member.name,
    }));
  }
  return crmState.unitMembers[unitId];
};

// Lembrete de tarefa: com o Chatwoot aberto, avisa quando chega a hora de uma tarefa do próprio
// usuário (até 2 horas depois do prazo, uma vez por tarefa e prazo). A lista é buscada a cada
// 5 minutos e só traz o que vence até o fim do dia.
const REMINDER_CHECK = 60 * 1000;
const REMINDER_REFRESH = 5 * 60 * 1000;
const REMINDER_WINDOW = 2 * 60 * 60 * 1000;
const REMINDED_KEY = 'outsider_crm_reminded';
let reminderTimer = null;
let reminderTasks = [];
let reminderFetchedAt = 0;
let reminderT = null;

const endOfToday = () => {
  const date = new Date();
  date.setHours(23, 59, 59, 999);
  return date.toISOString();
};

const readReminded = () => {
  try {
    return JSON.parse(localStorage.getItem(REMINDED_KEY) || '[]');
  } catch {
    return [];
  }
};

export const refreshMyTasks = async () => {
  try {
    const { data } = await CrmAPI.getTaskList({ due_before: endOfToday() });
    reminderTasks = data.payload;
    reminderFetchedAt = Date.now();
    // as contagens vêm de todas as pendentes, não só das de hoje
    crmState.myTasks = data.meta;
  } catch {
    // sem lembrete se a lista falhar
  }
};

const checkReminders = async () => {
  if (!crmState.access.enabled || !reminderT) return;
  if (Date.now() - reminderFetchedAt > REMINDER_REFRESH) await refreshMyTasks();
  const now = Date.now();
  const reminded = readReminded();
  const due = reminderTasks.filter(task => {
    if (!task.due_at) return false;
    const at = new Date(task.due_at).getTime();
    return (
      at <= now &&
      now - at < REMINDER_WINDOW &&
      !reminded.includes(`${task.id}-${task.due_at}`)
    );
  });
  if (!due.length) return;
  const to = frontendURL(`accounts/${crmState.accountId}/crm/tasks`);
  due.forEach(task => {
    useAlert(
      reminderT('OUTSIDER_CRM.TASKS.REMINDER', {
        title: task.title,
        contact: task.opportunity.contact?.name || task.opportunity.code,
      }),
      {
        type: 'link',
        to,
        message: reminderT('OUTSIDER_CRM.TASKS.REMINDER_LINK'),
        duration: 15000,
      }
    );
  });
  const keys = [...reminded, ...due.map(task => `${task.id}-${task.due_at}`)];
  try {
    localStorage.setItem(REMINDED_KEY, JSON.stringify(keys.slice(-200)));
  } catch {
    // navegador sem localStorage: o aviso pode repetir
  }
};

// chamado pela tela de conversas e pela tela do CRM; roda um relógio só
export const startTaskReminders = async t => {
  reminderT = t;
  await ensureCrmContext();
  if (reminderTimer || !crmState.access.enabled) return;
  reminderTimer = setInterval(checkReminders, REMINDER_CHECK);
  checkReminders();
};

// Aviso de negócio recebido por encaminhamento: a lista é buscada a cada minuto enquanto o Chatwoot
// está aberto (o ícone do CRM no menu lateral liga o relógio). Fechar o aviso marca "notified";
// abrir o negócio (painel do CRM ou aba da conversa) marca "opened" e tira a bolinha.
const RECEIVED_CHECK = 60 * 1000;
let receivedTimer = null;

export const refreshReceived = async () => {
  if (!crmState.access.enabled) return;
  try {
    const { data } = await CrmAPI.getReceivedForwards();
    crmState.received = data.payload;
  } catch {
    // sem aviso se a lista falhar; tenta de novo no próximo minuto
  }
};

export const startReceivedWatch = async () => {
  await ensureCrmContext();
  if (receivedTimer || !crmState.access.enabled) return;
  receivedTimer = setInterval(refreshReceived, RECEIVED_CHECK);
  refreshReceived();
};

export const isReceived = opportunityId =>
  crmState.received.some(item => item.opportunity_id === opportunityId);

export const markReceived = async (opportunityIds, opened) => {
  const ids = opportunityIds.filter(isReceived);
  if (!ids.length) return;
  // tira da tela na hora; a resposta traz a lista atualizada
  crmState.received = crmState.received
    .filter(item => !(opened && ids.includes(item.opportunity_id)))
    .map(item =>
      ids.includes(item.opportunity_id) ? { ...item, notified: true } : item
    );
  try {
    const { data } = await CrmAPI.markReceivedForwards(ids, opened);
    crmState.received = data.payload;
  } catch {
    // se falhar, o aviso volta na próxima busca
  }
};

// Atualização ao vivo (live.js): o que fica fora da tela do CRM também acompanha. Contagem de
// tarefas do menu, aviso de negócio recebido e o resumo dos contatos já abertos na conversa.
onCrmChange(changes => {
  if (!crmState.access.enabled) return;
  const all = changes.some(change => change.kind === 'reconnected');
  if (all || changes.some(change => change.kind !== 'config')) refreshMyTasks();
  if (all || changes.some(change => change.kind === 'opportunity')) {
    refreshReceived();
  }
  const contactIds = all
    ? Object.keys(crmState.histories)
        .concat(Object.keys(crmState.summaries).map(key => key.split('-')[0]))
        .map(Number)
    : changes.map(change => change.contact_id).filter(Boolean);
  changes.forEach(change => {
    if (change.kind === 'opportunity') bumpActivity(change.id);
    if (change.kind === 'task') bumpActivity(change.opportunity_id);
  });
  [...new Set(contactIds)]
    .filter(
      id =>
        id in crmState.chips ||
        crmState.histories[id] ||
        Object.keys(crmState.summaries).some(key => key.startsWith(`${id}-`))
    )
    .forEach(id => refreshContact(id).catch(() => {}));
});
