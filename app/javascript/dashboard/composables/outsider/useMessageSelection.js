// OUTSIDER: selecionar mensagens da conversa (como no WhatsApp) para encaminhar ou copiar várias
// de uma vez. Começa pelo menu da mensagem ("Selecionar mensagens"); cada mensagem tem uma camada
// (MessageSelectLayer.vue) que, no modo seleção, mostra a caixinha e marca/desmarca no clique; a
// barra (MessageSelectionBar.vue) fica no lugar da caixa de resposta. Esc ou trocar de conversa
// sai do modo seleção.
import { reactive, computed } from 'vue';

// cada mensagem na tela se registra aqui (id -> função que devolve os dados atuais dela)
const registry = new Map();

export const selection = reactive({
  active: false,
  conversationId: null,
  ids: [],
});

const setBodyClass = active =>
  document.body.classList.toggle('outsider-selecting', active);

const onKeydown = event => {
  if (event.key === 'Escape' && selection.active) {
    event.stopPropagation();
    // eslint-disable-next-line no-use-before-define
    stopSelection();
  }
};

export const stopSelection = () => {
  selection.active = false;
  selection.conversationId = null;
  selection.ids = [];
  setBodyClass(false);
  document.removeEventListener('keydown', onKeydown, true);
};

export const startSelection = (conversationId, firstId = null) => {
  selection.active = true;
  selection.conversationId = conversationId;
  selection.ids = firstId && registry.has(firstId) ? [firstId] : [];
  setBodyClass(true);
  document.addEventListener('keydown', onKeydown, true);
};

export const isSelected = id => selection.ids.includes(id);

export const toggleSelected = id => {
  selection.ids = isSelected(id)
    ? selection.ids.filter(item => item !== id)
    : [...selection.ids, id];
};

export const registerMessage = (id, getter) => registry.set(id, getter);
export const unregisterMessage = (id, getter) => {
  if (registry.get(id) === getter) registry.delete(id);
};

// mensagens escolhidas na ordem da conversa (as que saíram da tela continuam pelo último dado visto)
const snapshots = new Map();
export const selectedMessages = computed(() =>
  selection.ids
    .map(id => {
      const data = registry.get(id)?.();
      if (data) snapshots.set(id, data);
      return data || snapshots.get(id);
    })
    .filter(Boolean)
    .sort((a, b) => a.createdAt - b.createdAt || a.id - b.id)
);
