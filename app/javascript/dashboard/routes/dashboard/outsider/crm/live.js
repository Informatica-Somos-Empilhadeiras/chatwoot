// OUTSIDER: atualização ao vivo do CRM. Uma conexão própria com o servidor (canal
// Outsider::Crm::UpdatesChannel) recebe "algo mudou" quando alguém grava um negócio, uma tarefa, as
// metas ou as configurações. Os avisos próximos viram um só e as telas abertas recarregam pela API,
// que aplica as permissões de quem está vendo. Ao reconectar (queda de rede), recarregam também.
// O aviso de acesso (CRM ligado ou desligado na conta ou para alguém) vai à parte, para quem confere
// o acesso (onCrmAccessChange); as telas não recarregam por ele.
import { onBeforeUnmount, onMounted } from 'vue';
import { createConsumer } from '@rails/actioncable';
import store from 'dashboard/store';

const CHANNEL = 'Outsider::Crm::UpdatesChannel';
const BATCH_DELAY = 400;

const listeners = new Set();
const accessListeners = new Set();
let consumer = null;
let subscription = null;
let subscribedAccount = null;
let pending = [];
let timer = null;

const flush = () => {
  timer = null;
  const changes = pending;
  pending = [];
  listeners.forEach(listener => {
    try {
      listener(changes);
    } catch {
      // uma tela com erro não impede as outras de recarregar
    }
  });
};

const received = change => {
  if (change.kind === 'access') {
    accessListeners.forEach(listener => {
      try {
        listener(change);
      } catch {
        // um erro aqui não impede os outros de conferirem o acesso
      }
    });
    return;
  }
  pending.push(change);
  if (!timer) timer = setTimeout(flush, BATCH_DELAY);
};

export const startLiveUpdates = accountId => {
  const user = store.getters.getCurrentUser;
  if (!accountId || !user?.pubsub_token || subscribedAccount === accountId) {
    return;
  }
  if (!consumer) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    consumer = createConsumer(
      websocketURL ? `${websocketURL}/cable` : undefined
    );
  }
  subscription?.unsubscribe();
  subscribedAccount = accountId;
  let connectedBefore = false;
  subscription = consumer.subscriptions.create(
    {
      channel: CHANNEL,
      pubsub_token: user.pubsub_token,
      user_id: user.id,
      account_id: accountId,
    },
    {
      received,
      connected() {
        if (connectedBefore) received({ kind: 'reconnected' });
        connectedBefore = true;
      },
    }
  );
};

// conta com o CRM desligado: fecha a conexão (ligar a conta de novo aparece ao recarregar a página)
export const stopLiveUpdates = () => {
  subscription?.unsubscribe();
  subscription = null;
  subscribedAccount = null;
  consumer?.disconnect();
  consumer = null;
};

export const onCrmChange = listener => {
  listeners.add(listener);
  return () => listeners.delete(listener);
};

export const onCrmAccessChange = listener => {
  accessListeners.add(listener);
  return () => accessListeners.delete(listener);
};

// para telas: recarrega enquanto o componente está na tela
export const useCrmChanges = listener => {
  let stop = null;
  onMounted(() => {
    stop = onCrmChange(listener);
  });
  onBeforeUnmount(() => stop?.());
};
