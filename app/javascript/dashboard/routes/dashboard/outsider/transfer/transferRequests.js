// OUTSIDER: pedidos de transferência de conversa entre agentes, compartilhados pela busca (botão
// "Solicitar transferência") e pelos avisos (TransferNotices.vue).
//   incoming: pedidos que esperam resposta minha (a conversa está comigo)
//   outgoing: pedidos meus esperando resposta
//   answered: respostas aos meus pedidos que eu ainda não vi (recusado fica até o OK)
// Os avisos chegam pelo canal do usuário no Chatwoot (evento 'outsider.notice', repassado pelo
// actionCable.js); ao reconectar e de tempos em tempos a lista é buscada de novo.
import { reactive } from 'vue';
import TransferRequestsAPI from 'dashboard/api/outsider/transferRequests';
import {
  isSearchActive,
  useQuickSearch,
} from 'dashboard/composables/outsider/useQuickSearch';

export const NOTICE_EVENT = 'outsider:notice';

const LISTS = ['incoming', 'outgoing', 'answered'];

export const transferState = reactive({
  loaded: false,
  incoming: [],
  outgoing: [],
  answered: [],
  busy: {},
});

const removeEverywhere = id => {
  LISTS.forEach(list => {
    transferState[list] = transferState[list].filter(item => item.id !== id);
  });
};

const put = (list, request) => {
  removeEverywhere(request.id);
  transferState[list] = [...transferState[list], request];
};

// aplica um aviso do servidor (ou a resposta de uma ação minha)
export const applyTransferNotice = (action, request, userId) => {
  if (!request?.id) return;
  const iAmHolder = request.holder?.id === userId;
  const iAmRequester = request.requester?.id === userId;
  if (action === 'created') {
    if (iAmHolder) put('incoming', request);
    else if (iAmRequester) put('outgoing', request);
    return;
  }
  if (action === 'accepted' || action === 'declined') {
    if (iAmRequester) put('answered', request);
    else removeEverywhere(request.id);
    // a conversa mudou de dono: a busca aberta mostra de novo onde ela está
    if (action === 'accepted' && isSearchActive.value)
      useQuickSearch().refresh();
    return;
  }
  removeEverywhere(request.id);
};

export const fetchTransfers = async () => {
  const { data } = await TransferRequestsAPI.get();
  LISTS.forEach(list => {
    transferState[list] = data[list] || [];
  });
  transferState.loaded = true;
};

const withBusy = async (key, action) => {
  transferState.busy = { ...transferState.busy, [key]: true };
  try {
    return await action();
  } finally {
    const { [key]: _, ...rest } = transferState.busy;
    transferState.busy = rest;
  }
};

export const pendingRequestFor = conversationId =>
  transferState.outgoing.find(
    request => request.conversation?.id === conversationId
  );

export const requestTransfer = (conversationId, note) =>
  withBusy(`conversation-${conversationId}`, async () => {
    const { data } = await TransferRequestsAPI.request(conversationId, note);
    put('outgoing', data);
    return data;
  });

export const cancelTransfer = id =>
  withBusy(id, async () => {
    await TransferRequestsAPI.cancel(id);
    removeEverywhere(id);
  });

export const acceptTransfer = id =>
  withBusy(id, async () => {
    try {
      const { data } = await TransferRequestsAPI.accept(id);
      return data;
    } finally {
      removeEverywhere(id);
    }
  });

export const declineTransfer = (id, note) =>
  withBusy(id, async () => {
    try {
      await TransferRequestsAPI.decline(id, note);
    } finally {
      removeEverywhere(id);
    }
  });

export const acknowledgeTransfer = id =>
  withBusy(id, async () => {
    removeEverywhere(id);
    await TransferRequestsAPI.acknowledge(id);
  });
