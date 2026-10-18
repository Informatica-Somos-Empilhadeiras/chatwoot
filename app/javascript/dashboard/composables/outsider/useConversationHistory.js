// OUTSIDER: navegação no histórico da conversa aberta (busca, ir para uma data,
// separadores de dia). Estado único, compartilhado entre o MessagesView, o
// cabeçalho e o painel de busca.
//
// Ir até uma mensagem antiga que ainda não foi carregada abre uma "janela":
// as mensagens em volta dela são mostradas no lugar da lista da conversa, sem
// mexer na store (a lista da conversa, o card e as não lidas continuam certos).
// Rolando para baixo a janela vai carregando até encostar na lista da conversa;
// aí as duas viram uma só e a janela fecha.
//
// Enquanto alguém está lendo mensagens antigas, mensagem nova não puxa a tela
// para o fim: aparece o botão "ir para as mais recentes" com a contagem.

import { computed, nextTick, reactive, ref } from 'vue';
import store from 'dashboard/store';
import types from 'dashboard/store/mutation-types';
import MessageApi from 'dashboard/api/inbox/message';
import ConversationHistoryAPI from 'dashboard/api/outsider/conversationHistory';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_STATUS } from 'shared/constants/messages';
import {
  dateKeyOf,
  findMatches,
  firstServerId,
  isServerMessageId,
  lastServerId,
  mergeMessages,
} from 'dashboard/helper/outsider/conversationHistory';

const OLDER_PAGE = 20; // MessageFinder com `before`
const NEWER_PAGE = 100; // MessageFinder com `after`
const AT_BOTTOM_PX = 160;
const STICKY_DAY_OFFSET_PX = 56; // espaço do separador de dia fixo no topo
const HIGHLIGHT_NAME = 'outsider-search-hit';
const DAYS_CACHE_MS = 60 * 1000;
const TODAY_CHECK_MS = 60 * 1000;
const ACTIVITY_MESSAGE = 2;
const STALE_PUSH_SECONDS = 60;
const RE_REVEAL_MS = 4000;

export const historyState = reactive({
  conversationId: null,
  window: null, // { messages, startReached }
  jumping: false,
  loadingOlder: false,
  loadingNewer: false,
  readingHistory: false,
  baselineId: 0, // última mensagem que já existia quando a pessoa saiu do fim
  searchOpen: false,
  calendarOpen: false,
  calendarMonth: null,
});

// "AAAA-MM-DD" de hoje; muda sozinho na virada do dia ("Hoje" vira "Ontem")
export const todayKey = ref(dateKeyOf(new Date()));

let panel = null; // o <ul> que rola (MessageList)
let jumpSequence = 0;
let lastJump = null; // { id, terms, align, at } da última ida até uma mensagem
let unsubscribeStore = null;
let todayTimer = null;
const daysCache = new Map(); // conversa -> { at, days }

const selectedChat = () => store.getters.getSelectedChat;
const storeMessagesOf = chat => chat?.messages || [];

const nextJump = () => {
  jumpSequence += 1;
  return jumpSequence;
};

const distanceFromBottom = () =>
  panel ? panel.scrollHeight - panel.scrollTop - panel.clientHeight : 0;

export const isNearBottom = () => distanceFromBottom() < AT_BOTTOM_PX;

/** Mensagens que chegaram desde que a pessoa saiu do fim da conversa. */
export const newMessagesCount = computed(() => {
  const { baselineId } = historyState;
  if (!baselineId) return 0;
  return storeMessagesOf(selectedChat()).filter(
    message =>
      isServerMessageId(message.id) &&
      message.id > baselineId &&
      message.message_type !== ACTIVITY_MESSAGE
  ).length;
});

export const setReadingHistory = reading => {
  if (reading && !historyState.readingHistory) {
    historyState.baselineId = lastServerId(storeMessagesOf(selectedChat()));
  }
  if (!reading) historyState.baselineId = 0;
  historyState.readingHistory = reading;
};

/** Voltou para o fim: deixa de ler o histórico e marca como lidas. */
export const leaveReadingHistory = () => {
  if (!historyState.readingHistory) return;
  const chat = selectedChat();
  const hasUnread = newMessagesCount.value > 0 || chat?.unread_count > 0;
  setReadingHistory(false);
  if (hasUnread && chat?.id) {
    store.dispatch('markMessagesRead', { id: chat.id });
  }
};

export const clearTermHighlight = () => {
  window.CSS?.highlights?.delete(HIGHLIGHT_NAME);
};

/** A pessoa mexeu na rolagem: não reposiciona mais a última mensagem buscada. */
export const forgetLastJump = () => {
  lastJump = null;
};

export const resetHistory = conversationId => {
  nextJump();
  lastJump = null;
  clearTermHighlight();
  Object.assign(historyState, {
    conversationId,
    window: null,
    jumping: false,
    loadingOlder: false,
    loadingNewer: false,
    readingHistory: false,
    baselineId: 0,
    searchOpen: false,
    calendarOpen: false,
    calendarMonth: null,
  });
};

export const historyWindowMessages = conversationId =>
  historyState.window && historyState.conversationId === conversationId
    ? historyState.window.messages
    : null;

export const isHistoryWindowOpen = conversationId =>
  !!historyWindowMessages(conversationId);

const renderedMessageElement = messageId => {
  if (!panel) return null;
  const exact = panel.querySelector(`[data-message-id="${messageId}"]`);
  if (exact) return exact;
  // mensagem dentro de um álbum (só a primeira aparece) ou escondida:
  // usa a mais próxima antes dela
  const candidates = [...panel.querySelectorAll('[data-message-id]')];
  const before = candidates.filter(
    element => Number(element.dataset.messageId) <= messageId
  );
  return before[before.length - 1] || candidates[0] || null;
};

const highlightTerms = (element, terms) => {
  clearTermHighlight();
  if (!terms?.length || !window.CSS?.highlights || !window.Highlight) return;
  const ranges = [];
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode;
    findMatches(node.data, terms).forEach(([start, end]) => {
      const range = new Range();
      range.setStart(node, start);
      range.setEnd(node, end);
      ranges.push(range);
    });
  }
  if (ranges.length) {
    window.CSS.highlights.set(HIGHLIGHT_NAME, new window.Highlight(...ranges));
  }
};

const flash = element => {
  element.animate?.(
    [
      { backgroundColor: 'rgb(20 184 166 / 0.32)' },
      { backgroundColor: 'rgb(20 184 166 / 0.32)', offset: 0.35 },
      { backgroundColor: 'rgb(20 184 166 / 0)' },
    ],
    { duration: 2600, easing: 'ease-out' }
  );
};

// align "center": mensagem no meio da tela (resultado da busca);
// align "top": começo do dia (ou a mensagem) no alto da tela (ida até uma data)
const revealMessage = (messageId, terms, align, withFlash = true) => {
  const element = renderedMessageElement(messageId);
  if (!element || !panel) return;
  const panelTop = panel.getBoundingClientRect().top;
  const separator = element.previousElementSibling?.matches(
    '[data-outsider-day]'
  )
    ? element.previousElementSibling
    : null;
  let delta;
  if (align === 'top') {
    delta = separator
      ? separator.getBoundingClientRect().top - panelTop - 8
      : element.getBoundingClientRect().top - panelTop - STICKY_DAY_OFFSET_PX;
  } else {
    const { top, height } = element.getBoundingClientRect();
    const free = panel.clientHeight - height;
    const offset =
      free > STICKY_DAY_OFFSET_PX * 2 ? free / 2 : STICKY_DAY_OFFSET_PX;
    delta = top - panelTop - offset;
  }
  panel.scrollTop += delta;
  if (historyState.window || distanceFromBottom() >= AT_BOTTOM_PX) {
    setReadingHistory(true);
  } else {
    leaveReadingHistory();
  }
  if (withFlash) flash(element);
  highlightTerms(element, terms);
};

// a página antiga que o Chatwoot pediu chegou depois da ida até a mensagem
// e empurrou a tela: põe a mensagem de volta no lugar
const reRevealAfterRace = () => {
  const jump = lastJump;
  if (!jump || performance.now() - jump.at > RE_REVEAL_MS) return;
  nextTick(() =>
    requestAnimationFrame(() => {
      if (jump === lastJump) {
        revealMessage(jump.id, jump.terms, jump.align, false);
      }
    })
  );
};

// mantém a cópia da janela igual à store (mensagem apagada, status de entrega...)
const updateWindowCopy = message => {
  const currentWindow = historyState.window;
  if (!currentWindow || message.conversation_id !== historyState.conversationId)
    return;
  const index = currentWindow.messages.findIndex(m => m.id === message.id);
  if (index === -1) return;
  currentWindow.messages[index] = {
    ...currentWindow.messages[index],
    ...message,
  };
};

// Atualização de uma mensagem antiga que a store não tinha (apagar uma mensagem
// achada pela busca, status de entrega de uma antiga...): o Chatwoot a coloca no
// fim da lista e muda a hora da conversa. Põe no lugar certo, ou tira se ela é
// mais antiga que tudo que está carregado, e devolve a hora da conversa.
const dropStalePush = message => {
  if (!isServerMessageId(message.id)) return;
  const chat = store.getters.getConversationById(message.conversation_id);
  const list = storeMessagesOf(chat);
  if (list[list.length - 1]?.id !== message.id) return;
  const rest = list.slice(0, -1);
  const newest = rest.findLast(m => isServerMessageId(m.id));
  if (!newest || newest.id < message.id) return;
  if (newest.created_at - message.created_at < STALE_PUSH_SECONDS) return;

  store.commit(types.SET_MISSING_MESSAGES, {
    id: chat.id,
    data:
      message.id > firstServerId(rest) ? mergeMessages(rest, [message]) : rest,
  });
  chat.timestamp = Math.max(chat.last_activity_at || 0, newest.created_at);
};

// página antiga do Chatwoot chegando depois de a janela virar parte da store
const tidyPreviousPage = conversationId => {
  const chat = store.getters.getConversationById(conversationId);
  const list = storeMessagesOf(chat);
  if (new Set(list.map(message => message.id)).size !== list.length) {
    store.commit(types.SET_MISSING_MESSAGES, {
      id: chat.id,
      data: mergeMessages(list),
    });
  }
  if (conversationId === historyState.conversationId) reRevealAfterRace();
};

const keepStoreTidy = mutation => {
  if (mutation.type === types.ADD_MESSAGE && mutation.payload) {
    updateWindowCopy(mutation.payload);
    dropStalePush(mutation.payload);
  } else if (mutation.type === types.SET_PREVIOUS_CONVERSATIONS) {
    tidyPreviousPage(mutation.payload?.id);
  }
};

const refreshToday = () => {
  todayKey.value = dateKeyOf(new Date());
};

export const registerPanel = element => {
  panel = element;
  if (element && !unsubscribeStore) {
    unsubscribeStore = store.subscribe(keepStoreTidy);
    refreshToday();
    todayTimer = setInterval(refreshToday, TODAY_CHECK_MS);
  } else if (!element && unsubscribeStore) {
    unsubscribeStore();
    unsubscribeStore = null;
    clearInterval(todayTimer);
  }
};

// a janela encostou na lista da conversa: vira uma lista só na store
const joinWithStore = (chat, messages, startReached) => {
  store.commit(types.SET_MISSING_MESSAGES, {
    id: chat.id,
    data: mergeMessages(messages, storeMessagesOf(chat)),
  });
  if (startReached) store.commit(types.SET_ALL_MESSAGES_LOADED, chat.id);
  historyState.window = null;
};

const touchesStore = (chat, messages, endReached) => {
  const storeFirst = firstServerId(storeMessagesOf(chat));
  return endReached || (storeFirst && lastServerId(messages) >= storeFirst);
};

const fetchAround = async (chat, messageId) => {
  const [older, newer] = await Promise.all([
    MessageApi.getPreviousMessages({
      conversationId: chat.id,
      before: messageId,
    }),
    MessageApi.getPreviousMessages({
      conversationId: chat.id,
      after: messageId - 1,
    }),
  ]);
  return { older: older.data.payload, newer: newer.data.payload };
};

const showAround = (chat, { older, newer }) => {
  const messages = mergeMessages(older, newer);
  const startReached = older.length < OLDER_PAGE;
  if (touchesStore(chat, messages, newer.length < NEWER_PAGE)) {
    joinWithStore(chat, messages, startReached);
  } else {
    historyState.window = { messages, startReached };
  }
};

const isDisplayed = (chat, messageId) =>
  (historyWindowMessages(chat.id) || storeMessagesOf(chat)).some(
    message => message.id === messageId
  );

/**
 * Leva a conversa aberta até a mensagem, carregando o trecho dela se preciso.
 * terms: palavras da busca para destacar dentro do balão; align: ver revealMessage.
 * Devolve false se não conseguiu carregar o trecho.
 */
export const jumpToMessage = async (
  messageId,
  { terms = [], align = 'center', sequence = nextJump() } = {}
) => {
  const chat = selectedChat();
  const id = Number(messageId);
  if (!chat?.id || !id) return false;
  const isCurrent = () => sequence === jumpSequence;

  if (!isDisplayed(chat, id)) {
    if (storeMessagesOf(chat).some(message => message.id === id)) {
      historyState.window = null;
    } else {
      historyState.jumping = true;
      try {
        const around = await fetchAround(chat, id);
        if (!isCurrent()) return true;
        showAround(chat, around);
      } catch (error) {
        if (!isCurrent()) return true;
        historyState.jumping = false;
        return false;
      }
    }
  }
  if (!isCurrent()) return true;
  historyState.jumping = false;
  await nextTick();
  requestAnimationFrame(() => {
    if (!isCurrent()) return;
    lastJump = { id, terms, align, at: performance.now() };
    revealMessage(id, terms, align);
  });
  return true;
};

/** Vai para a primeira mensagem a partir do horário (segundos). */
export const jumpToTime = async unix => {
  const chat = selectedChat();
  if (!chat?.id) return false;
  const sequence = nextJump();
  historyState.jumping = true;
  try {
    const { data } = await ConversationHistoryAPI.locate(chat.id, unix);
    if (sequence !== jumpSequence) return true;
    return await jumpToMessage(data.message_id, { align: 'top', sequence });
  } catch (error) {
    return false;
  } finally {
    if (sequence === jumpSequence) historyState.jumping = false;
  }
};

export const returnToLatest = () => {
  nextJump();
  lastJump = null;
  clearTermHighlight();
  historyState.window = null;
  historyState.jumping = false;
  setReadingHistory(false);
  // caminho normal do Chatwoot: rola até o fim e marca como lidas
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
};

export const loadOlder = async () => {
  const currentWindow = historyState.window;
  if (!currentWindow || currentWindow.startReached) return;
  if (historyState.loadingOlder || !panel) return;
  const chat = selectedChat();
  historyState.loadingOlder = true;
  try {
    const { data } = await MessageApi.getPreviousMessages({
      conversationId: chat.id,
      before: firstServerId(currentWindow.messages),
    });
    if (historyState.window !== currentWindow) return;
    const heightBefore = panel.scrollHeight;
    const topBefore = panel.scrollTop;
    currentWindow.messages = mergeMessages(
      data.payload,
      currentWindow.messages
    );
    currentWindow.startReached = data.payload.length < OLDER_PAGE;
    await nextTick();
    panel.scrollTop = topBefore + (panel.scrollHeight - heightBefore);
  } finally {
    historyState.loadingOlder = false;
  }
};

export const loadNewer = async () => {
  const currentWindow = historyState.window;
  if (!currentWindow || historyState.loadingNewer) return;
  const chat = selectedChat();
  historyState.loadingNewer = true;
  try {
    const { data } = await MessageApi.getPreviousMessages({
      conversationId: chat.id,
      after: lastServerId(currentWindow.messages),
    });
    if (historyState.window !== currentWindow) return;
    const messages = mergeMessages(currentWindow.messages, data.payload);
    if (touchesStore(chat, messages, data.payload.length < NEWER_PAGE)) {
      joinWithStore(chat, messages, currentWindow.startReached);
    } else {
      currentWindow.messages = messages;
    }
  } finally {
    historyState.loadingNewer = false;
  }
};

// a última mensagem é a que o próprio agente acabou de mandar (ainda sem id do servidor)
const justSentByAgent = chat => {
  const list = storeMessagesOf(chat);
  const last = list[list.length - 1];
  return (
    last?.status === MESSAGE_STATUS.PROGRESS && !isServerMessageId(last.id)
  );
};

/**
 * Chamado no começo do MessagesView.onScrollToMessage.
 * Devolve true quando este módulo cuida do pedido de rolagem.
 */
export const interceptScrollRequest = messageId => {
  const chat = selectedChat();
  if (!chat?.id || historyState.conversationId !== chat.id) return false;

  if (messageId) {
    jumpToMessage(messageId);
    store.dispatch('markMessagesRead', { id: chat.id });
    return true;
  }
  if (!historyState.window && !historyState.readingHistory) return false;
  if (justSentByAgent(chat)) {
    // o próprio agente enviou: volta para o fim, como no WhatsApp
    nextJump();
    lastJump = null;
    historyState.window = null;
    historyState.jumping = false;
    setReadingHistory(false);
    return false;
  }
  return true;
};

export const openSearch = () => {
  const chat = selectedChat();
  if (chat?.id && historyState.conversationId !== chat.id) {
    resetHistory(chat.id);
  }
  historyState.searchOpen = true;
};

export const closeSearch = () => {
  historyState.searchOpen = false;
  historyState.calendarOpen = false;
  clearTermHighlight();
};

export const openCalendar = (dateKey = null) => {
  openSearch();
  historyState.calendarMonth = dateKey ? dateKey.slice(0, 7) : null;
  historyState.calendarOpen = true;
};

/** { "AAAA-MM-DD": quantidade } da conversa, no fuso de quem está olhando */
export const fetchMessageDays = async conversationId => {
  const cached = daysCache.get(conversationId);
  if (cached && performance.now() - cached.at < DAYS_CACHE_MS) {
    return cached.days;
  }
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const { data } = await ConversationHistoryAPI.days(conversationId, timeZone);
  daysCache.set(conversationId, { at: performance.now(), days: data.days });
  return data.days;
};
