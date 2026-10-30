// OUTSIDER: estado da busca da lista de conversas, como a do WhatsApp. A barra de busca escreve aqui
// e o painel de resultados (QuickSearchResults.vue) lê daqui: conversas, conversas com outros
// agentes, contatos e mensagens. Duas consultas em paralelo: conversas e contatos (rápida) e
// mensagens (índice trigram, pode demorar um pouco mais numa conta grande). Só vale a resposta da
// última busca: quem digita rápido cancela as anteriores.
import { reactive, computed } from 'vue';
import { debounce } from '@chatwoot/utils';
import store from 'dashboard/store';
import ConversationSearchAPI from 'dashboard/api/outsider/conversationSearch';

const MIN_QUERY = 2;
const MIN_MESSAGE_TERM = 3;
const DEBOUNCE = 250;

const ACCENTS = 'áàâãäåéèêëíìîïóòôõöúùûüýÿçñ';
const PLAIN = 'aaaaaaeeeeiiiiooooouuuuyycn';

export const foldText = text =>
  String(text || '')
    .toLowerCase()
    .replace(/[áàâãäåéèêëíìîïóòôõöúùûüýÿçñ]/g, c => PLAIN[ACCENTS.indexOf(c)]);

const emptyMessages = () => ({
  list: [],
  hasMore: false,
  loading: false,
  loadingMore: false,
  tooShort: false,
  timeout: false,
  error: false,
});

const state = reactive({
  query: '',
  loading: false,
  error: false,
  conversations: [],
  locked: [],
  contacts: [],
  messages: emptyMessages(),
});

let mainController = null;
let messagesController = null;

const trimmedQuery = () => state.query.trim();

export const searchTerms = computed(() =>
  foldText(trimmedQuery())
    .split(/\s+/)
    .filter(term => term.length >= MIN_QUERY)
);

export const isSearchActive = computed(
  () => trimmedQuery().length >= MIN_QUERY
);

const abortAll = () => {
  mainController?.abort();
  messagesController?.abort();
  mainController = null;
  messagesController = null;
};

const resetResults = () => {
  state.loading = false;
  state.error = false;
  state.conversations = [];
  state.locked = [];
  state.contacts = [];
  state.messages = emptyMessages();
};

const isAbort = error =>
  error?.name === 'CanceledError' || error?.code === 'ERR_CANCELED';

const fetchMain = async q => {
  mainController = new AbortController();
  const controller = mainController;
  state.loading = true;
  state.error = false;
  try {
    const { data } = await ConversationSearchAPI.search(q, controller.signal);
    if (controller !== mainController) return;
    const conversations = data.payload || [];
    // o card da lista pega o nome e a foto do contato na store
    conversations.forEach(conversation =>
      store.dispatch('contacts/setContact', conversation.meta.sender)
    );
    state.conversations = conversations.filter(c => !c.outsider_locked);
    state.locked = conversations.filter(c => c.outsider_locked);
    state.contacts = data.contacts || [];
  } catch (error) {
    if (isAbort(error) || controller !== mainController) return;
    state.error = true;
    state.conversations = [];
    state.locked = [];
    state.contacts = [];
  } finally {
    if (controller === mainController) state.loading = false;
  }
};

const fetchMessages = async (q, beforeId) => {
  const hasLongTerm = searchTerms.value.some(
    term => term.length >= MIN_MESSAGE_TERM
  );
  if (!hasLongTerm) {
    state.messages = { ...emptyMessages(), tooShort: true };
    return;
  }
  messagesController?.abort();
  messagesController = new AbortController();
  const controller = messagesController;
  const flag = beforeId ? 'loadingMore' : 'loading';
  state.messages[flag] = true;
  state.messages.error = false;
  state.messages.tooShort = false;
  try {
    const { data } = await ConversationSearchAPI.searchMessages(
      q,
      beforeId,
      controller.signal
    );
    if (controller !== messagesController) return;
    state.messages.list = beforeId
      ? [...state.messages.list, ...data.payload]
      : data.payload;
    state.messages.hasMore = data.has_more;
    state.messages.timeout = !!data.timeout;
  } catch (error) {
    if (isAbort(error) || controller !== messagesController) return;
    state.messages.error = true;
  } finally {
    if (controller === messagesController) state.messages[flag] = false;
  }
};

const runNow = () => {
  const q = trimmedQuery();
  abortAll();
  if (q.length < MIN_QUERY) {
    resetResults();
    return;
  }
  state.messages = emptyMessages();
  fetchMain(q);
  fetchMessages(q);
};

const runDebounced = debounce(runNow, DEBOUNCE);

export const useQuickSearch = () => {
  const setQuery = value => {
    state.query = value;
    if (trimmedQuery().length < MIN_QUERY) {
      abortAll();
      resetResults();
      return;
    }
    state.loading = true;
    runDebounced();
  };

  const clear = () => {
    state.query = '';
    abortAll();
    resetResults();
  };

  const loadMoreMessages = () => {
    const { list, hasMore, loadingMore } = state.messages;
    if (!hasMore || loadingMore || !list.length) return;
    fetchMessages(trimmedQuery(), list[list.length - 1].id);
  };

  return {
    state,
    isSearchActive,
    searchTerms,
    setQuery,
    clear,
    refresh: runNow,
    loadMoreMessages,
  };
};

// pedaços do texto com as palavras buscadas marcadas (sem v-html: cada pedaço vira um span)
export const highlightParts = (text, terms) => {
  const source = String(text || '');
  const folded = foldText(source);
  const ranges = [];
  terms.forEach(term => {
    let from = folded.indexOf(term);
    while (term && from !== -1) {
      ranges.push([from, from + term.length]);
      from = folded.indexOf(term, from + term.length);
    }
  });
  if (!ranges.length || folded.length !== source.length) {
    return [{ text: source, match: false }];
  }
  ranges.sort((a, b) => a[0] - b[0]);
  const parts = [];
  let cursor = 0;
  ranges.forEach(([start, end]) => {
    if (end <= cursor) return;
    const begin = Math.max(start, cursor);
    if (begin > cursor) {
      parts.push({ text: source.slice(cursor, begin), match: false });
    }
    parts.push({ text: source.slice(begin, end), match: true });
    cursor = end;
  });
  if (cursor < source.length) {
    parts.push({ text: source.slice(cursor), match: false });
  }
  return parts;
};
