<script setup>
// OUTSIDER: busca dentro da conversa, logo abaixo do cabeçalho (ver ConversationBox.vue).
// - busca sem acento e sem diferença de maiúsculas, todas as palavras em qualquer ordem;
// - resultados do mais novo para o mais antigo, com o trecho da mensagem destacado;
// - setas (ou Enter / Shift+Enter) passam pelos resultados e levam até cada mensagem;
// - filtro de data pelo calendário: escolher o dia já leva até ele (hora opcional)
//   e, se houver texto, mostra só os resultados daquele dia.
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useEventListener } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import HistoryCalendar from './HistoryCalendar.vue';
import ConversationHistoryAPI from 'dashboard/api/outsider/conversationHistory';
import {
  closeSearch,
  historyState,
  jumpToMessage,
  jumpToTime,
  returnToLatest,
} from 'dashboard/composables/outsider/useConversationHistory';
import {
  MIN_TERM_LENGTH,
  buildSnippet,
  dateFromKey,
  formatDate,
  searchTerms,
  unixEndOfKey,
  unixFromKey,
} from 'dashboard/helper/outsider/conversationHistory';

const props = defineProps({
  conversationId: { type: Number, required: true },
});

const DEBOUNCE_MS = 250;
const CACHE_SIZE = 30;
const CACHE_MS = 30 * 1000; // mensagens novas aparecem numa busca repetida depois disso
const PRIVATE_NOTE_COLOR = 'text-n-amber-11';
const HIT_CLASS = 'px-0.5 font-semibold rounded bg-n-amber-5 text-n-slate-12';

const { t, locale } = useI18n();

const inputRef = ref(null);
const query = ref('');
const dateKey = ref(null);
const time = ref('');
const results = ref([]);
const total = ref(null);
const totalMore = ref(false); // passou do limite que o servidor conta
const shownKey = ref(''); // busca (texto + data) a que os resultados mostrados pertencem
const hasMore = ref(false);
const loading = ref(false);
const loadingMore = ref(false);
const failed = ref(false);
const activeIndex = ref(-1);
const listOpen = ref(true);

const cache = new Map(); // chave -> { at, data }
let debounceTimer = null;
let controller = null;
let moreController = null;
let requestSequence = 0;

const isOpen = computed(
  () =>
    historyState.searchOpen &&
    historyState.conversationId === props.conversationId
);

const terms = computed(() => searchTerms(query.value));
const hasText = computed(() => query.value.trim().length > 0);
const tooShort = computed(() => hasText.value && !terms.value.length);

const range = computed(() =>
  dateKey.value
    ? { since: unixFromKey(dateKey.value), until: unixEndOfKey(dateKey.value) }
    : {}
);

const cacheKey = computed(
  () =>
    `${props.conversationId}|${terms.value.join(' ')}|${range.value.since || ''}`
);

// texto ou data mudou e os resultados na tela ainda são da busca anterior
const isStale = computed(
  () => terms.value.length > 0 && shownKey.value !== cacheKey.value
);

const dateChipLabel = computed(() => {
  if (!dateKey.value) return t('CONVERSATION.OUTSIDER_HISTORY.DATE');
  const date = formatDate(dateFromKey(dateKey.value), locale.value, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
  return time.value ? `${date} · ${time.value}` : date;
});

const counterLabel = computed(() => {
  if (total.value === null) return '';
  const totalLabel = totalMore.value ? `${total.value}+` : total.value;
  if (activeIndex.value >= 0) {
    return t('CONVERSATION.OUTSIDER_HISTORY.COUNTER', {
      current: activeIndex.value + 1,
      total: totalLabel,
    });
  }
  return total.value === 1
    ? t('CONVERSATION.OUTSIDER_HISTORY.RESULTS_ONE')
    : t('CONVERSATION.OUTSIDER_HISTORY.RESULTS_OTHER', { count: totalLabel });
});

const canGoOlder = computed(
  () =>
    !isStale.value &&
    (activeIndex.value < results.value.length - 1 || hasMore.value)
);
const canGoNewer = computed(() => !isStale.value && activeIndex.value > 0);

const showDropdown = computed(
  () =>
    listOpen.value &&
    !historyState.calendarOpen &&
    hasText.value &&
    (tooShort.value || failed.value || total.value !== null)
);

const resetResults = () => {
  results.value = [];
  total.value = null;
  totalMore.value = false;
  shownKey.value = '';
  hasMore.value = false;
  activeIndex.value = -1;
  failed.value = false;
};

const applyFirstPage = (data, key) => {
  results.value = data.payload;
  total.value = data.total;
  totalMore.value = data.total_more;
  shownKey.value = key;
  hasMore.value = data.has_more;
  activeIndex.value = -1;
};

const request = async (signal, beforeId) => {
  const { data } = await ConversationHistoryAPI.search(
    props.conversationId,
    { q: terms.value.join(' '), ...range.value, beforeId },
    signal
  );
  return data;
};

const cancelRequests = () => {
  controller?.abort();
  moreController?.abort();
  loadingMore.value = false;
};

const cached = key => {
  const entry = cache.get(key);
  if (entry && performance.now() - entry.at < CACHE_MS) return entry.data;
  cache.delete(key);
  return null;
};

const runSearch = async () => {
  clearTimeout(debounceTimer);
  debounceTimer = null;
  requestSequence += 1;
  const sequence = requestSequence;
  cancelRequests();
  failed.value = false;
  if (!terms.value.length) {
    loading.value = false;
    resetResults();
    return;
  }
  const key = cacheKey.value;
  const fromCache = cached(key);
  if (fromCache) {
    loading.value = false;
    applyFirstPage(fromCache, key);
    return;
  }
  loading.value = true;
  controller = new AbortController();
  try {
    const data = await request(controller.signal);
    if (sequence !== requestSequence) return;
    cache.set(key, { at: performance.now(), data });
    if (cache.size > CACHE_SIZE) cache.delete(cache.keys().next().value);
    applyFirstPage(data, key);
  } catch (error) {
    const canceled = ['CanceledError', 'AbortError'].includes(error?.name);
    if (sequence === requestSequence && !canceled) {
      resetResults();
      failed.value = true;
    }
  } finally {
    if (sequence === requestSequence) loading.value = false;
  }
};

const loadMore = async () => {
  if (!hasMore.value || loadingMore.value || isStale.value) return;
  const sequence = requestSequence;
  loadingMore.value = true;
  moreController = new AbortController();
  try {
    const data = await request(
      moreController.signal,
      results.value[results.value.length - 1].id
    );
    if (sequence !== requestSequence) return;
    results.value = [...results.value, ...data.payload];
    hasMore.value = data.has_more;
  } catch (error) {
    // a lista continua com o que já veio
  } finally {
    if (sequence === requestSequence) loadingMore.value = false;
  }
};

watch([terms, range], ([newTerms], [oldTerms]) => {
  // texto novo abre a lista; trocar só a data deixa a conversa à vista
  if (newTerms.join(' ') !== oldTerms.join(' ')) listOpen.value = true;
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(runSearch, DEBOUNCE_MS);
});

const goTo = async index => {
  if (index < 0) return;
  if (index >= results.value.length) await loadMore();
  if (index >= results.value.length) return;
  activeIndex.value = index;
  listOpen.value = false;
  const found = await jumpToMessage(results.value[index].id, {
    terms: terms.value,
  });
  if (!found) useAlert(t('CONVERSATION.OUTSIDER_HISTORY.JUMP_ERROR'));
};

const goOlder = () => goTo(activeIndex.value + 1);
const goNewer = () => goTo(activeIndex.value - 1);

// Enter logo depois de digitar: busca na hora (sem esperar a pausa) e vai ao primeiro
const onEnter = async event => {
  if (!terms.value.length) return;
  if (isStale.value) {
    await runSearch();
    if (isStale.value) return;
  }
  if (event.shiftKey) goNewer();
  else goOlder();
};

const close = () => {
  closeSearch();
};

const onEscape = () => {
  if (historyState.calendarOpen) historyState.calendarOpen = false;
  else close();
};

const clearText = () => {
  query.value = '';
  inputRef.value?.focus();
};

const toggleCalendar = () => {
  if (!historyState.calendarOpen) historyState.calendarMonth = null;
  historyState.calendarOpen = !historyState.calendarOpen;
};

const closeCalendar = () => {
  historyState.calendarOpen = false;
};

// Esc fecha o calendário mesmo com o foco fora da barra (aberto pela etiqueta do dia)
useEventListener(document, 'keydown', event => {
  if (event.key === 'Escape' && historyState.calendarOpen) closeCalendar();
});

const clearDate = () => {
  dateKey.value = null;
  time.value = '';
};

const goToDate = async (key, chosenTime) => {
  const found = await jumpToTime(unixFromKey(key, chosenTime));
  if (!found) useAlert(t('CONVERSATION.OUTSIDER_HISTORY.JUMP_ERROR'));
};

const onSelectDate = ({ dateKey: key, time: chosenTime }) => {
  dateKey.value = key;
  time.value = chosenTime || '';
  closeCalendar();
  goToDate(key, chosenTime);
};

const onJumpStart = async () => {
  closeCalendar();
  if (!(await jumpToTime(0))) {
    useAlert(t('CONVERSATION.OUTSIDER_HISTORY.JUMP_ERROR'));
  }
};

const onJumpLatest = () => {
  closeCalendar();
  returnToLatest();
};

const resultItems = computed(() =>
  results.value.map(message => {
    const snippet = buildSnippet(message.content, terms.value);
    return {
      message,
      snippet,
      sender: snippet.header || message.sender?.name || '',
      when: formatDate(new Date(message.created_at * 1000), locale.value, {
        day: '2-digit',
        month: '2-digit',
        year: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      }),
    };
  })
);

watch(
  isOpen,
  open => {
    if (open) {
      nextTick(() => inputRef.value?.focus());
      // a busca foi cancelada ao fechar: refaz com o que está escrito
      if (isStale.value && !loading.value) runSearch();
      return;
    }
    clearTimeout(debounceTimer);
    requestSequence += 1;
    cancelRequests();
    loading.value = false;
  },
  { immediate: true }
);

watch(
  () => props.conversationId,
  () => {
    query.value = '';
    clearDate();
    resetResults();
    cache.clear();
  }
);

onBeforeUnmount(() => {
  clearTimeout(debounceTimer);
  cancelRequests();
});
</script>

<template>
  <div
    v-show="isOpen"
    v-on-click-outside="() => (listOpen = false)"
    class="relative z-30 flex flex-wrap items-center gap-2 px-3 py-2 border-b bg-n-solid-2 border-n-weak"
    @keydown.esc.stop="onEscape"
  >
    <div
      class="flex items-center flex-1 min-w-[12rem] gap-2 px-3 rounded-lg h-9 bg-n-solid-1 ring-1 ring-n-strong focus-within:ring-2 focus-within:ring-n-teal-9"
    >
      <Spinner v-if="loading" :size="16" class="shrink-0 text-n-teal-10" />
      <span v-else class="i-lucide-search size-4 shrink-0 text-n-slate-10" />
      <input
        ref="inputRef"
        v-model="query"
        type="text"
        class="reset-base !mb-0 flex-1 min-w-0 h-full text-sm bg-transparent border-0 outline-none text-n-slate-12 placeholder:text-n-slate-10"
        :placeholder="t('CONVERSATION.OUTSIDER_HISTORY.PLACEHOLDER')"
        @keydown.enter.prevent="onEnter"
        @input="closeCalendar"
        @focus="listOpen = true"
      />
      <NextButton
        v-if="query"
        icon="i-lucide-x"
        size="xs"
        color="slate"
        variant="ghost"
        :title="t('CONVERSATION.OUTSIDER_HISTORY.CLEAR_TEXT')"
        @click="clearText"
      />
    </div>

    <div v-on-click-outside="closeCalendar" class="relative">
      <div
        class="flex items-center h-9 rounded-lg ring-1"
        :class="
          dateKey
            ? 'bg-n-teal-3 ring-n-teal-8 text-n-teal-11'
            : 'bg-n-solid-1 ring-n-strong text-n-slate-12'
        "
      >
        <button
          type="button"
          class="flex items-center h-full gap-2 px-3 text-sm font-medium"
          :title="t('CONVERSATION.OUTSIDER_HISTORY.GO_TO_DATE')"
          @click="toggleCalendar"
        >
          <span class="i-lucide-calendar-days size-4" />
          {{ dateChipLabel }}
        </button>
        <button
          v-if="dateKey"
          type="button"
          class="flex items-center justify-center h-full pr-2"
          :title="t('CONVERSATION.OUTSIDER_HISTORY.CLEAR_DATE')"
          @click="clearDate"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>
      <HistoryCalendar
        v-if="historyState.calendarOpen"
        class="absolute mt-2 top-full ltr:right-0 rtl:left-0"
        :conversation-id="conversationId"
        :month="historyState.calendarMonth"
        :selected-key="dateKey"
        :time="time"
        @select="onSelectDate"
        @jump-start="onJumpStart"
        @jump-latest="onJumpLatest"
      />
    </div>

    <div class="flex items-center gap-1">
      <span
        v-if="counterLabel"
        class="px-1 text-sm font-medium whitespace-nowrap text-n-slate-11"
        :class="{ 'opacity-50': isStale }"
      >
        {{ counterLabel }}
      </span>
      <NextButton
        v-tooltip.bottom="t('CONVERSATION.OUTSIDER_HISTORY.OLDER_RESULT')"
        icon="i-lucide-chevron-up"
        size="sm"
        color="slate"
        variant="faded"
        :disabled="!canGoOlder"
        @click="goOlder"
      />
      <NextButton
        v-tooltip.bottom="t('CONVERSATION.OUTSIDER_HISTORY.NEWER_RESULT')"
        icon="i-lucide-chevron-down"
        size="sm"
        color="slate"
        variant="faded"
        :disabled="!canGoNewer"
        @click="goNewer"
      />
      <NextButton
        v-if="results.length && !listOpen"
        v-tooltip.bottom="t('CONVERSATION.OUTSIDER_HISTORY.SHOW_LIST')"
        icon="i-lucide-list"
        size="sm"
        color="slate"
        variant="faded"
        @click="listOpen = true"
      />
      <NextButton
        v-tooltip.bottom="t('CONVERSATION.OUTSIDER_HISTORY.CLOSE')"
        icon="i-lucide-x"
        size="sm"
        color="slate"
        variant="ghost"
        @click="close"
      />
    </div>

    <div
      v-if="showDropdown"
      class="absolute inset-x-3 top-full mt-1 overflow-y-auto rounded-xl shadow-xl max-h-[min(28rem,60vh)] bg-n-solid-1 ring-1 ring-n-strong"
    >
      <p v-if="tooShort" class="px-4 py-3 m-0 text-sm text-n-slate-11">
        {{
          t('CONVERSATION.OUTSIDER_HISTORY.MIN_LETTERS', {
            count: MIN_TERM_LENGTH,
          })
        }}
      </p>
      <p v-else-if="failed" class="px-4 py-3 m-0 text-sm text-n-ruby-11">
        {{ t('CONVERSATION.OUTSIDER_HISTORY.SEARCH_ERROR') }}
      </p>
      <p
        v-else-if="!results.length"
        class="px-4 py-3 m-0 text-sm text-n-slate-11"
      >
        {{
          dateKey
            ? t('CONVERSATION.OUTSIDER_HISTORY.NO_RESULTS_DAY')
            : t('CONVERSATION.OUTSIDER_HISTORY.NO_RESULTS')
        }}
      </p>
      <template v-else>
        <button
          v-for="({ message, snippet, sender, when }, index) in resultItems"
          :key="message.id"
          type="button"
          class="flex flex-col w-full gap-1 px-4 py-2.5 text-left border-b border-n-weak last:border-b-0 hover:bg-n-alpha-2"
          :class="{ 'bg-n-teal-2': index === activeIndex }"
          @click="goTo(index)"
        >
          <span class="flex items-center w-full gap-2 text-xs">
            <span
              class="font-semibold truncate"
              :class="message.private ? PRIVATE_NOTE_COLOR : 'text-n-slate-12'"
            >
              {{ sender }}
            </span>
            <span
              v-if="message.private"
              class="px-1.5 rounded bg-n-amber-3 text-n-amber-11"
            >
              {{ t('CONVERSATION.OUTSIDER_HISTORY.PRIVATE_NOTE') }}
            </span>
            <span
              v-if="message.attachment_type"
              class="i-lucide-paperclip size-3.5 text-n-slate-10"
            />
            <span class="ml-auto whitespace-nowrap text-n-slate-10">
              {{ when }}
            </span>
          </span>
          <span
            class="text-sm leading-snug break-words text-n-slate-11 line-clamp-2"
          >
            <template
              v-for="(part, partIndex) in snippet.parts"
              :key="partIndex"
            >
              <mark v-if="part.hit" :class="HIT_CLASS">{{ part.text }}</mark>
              <template v-else>{{ part.text }}</template>
            </template>
          </span>
        </button>
        <button
          v-if="hasMore"
          type="button"
          class="flex items-center justify-center w-full gap-2 py-2.5 text-sm font-medium text-n-teal-11 hover:bg-n-alpha-2"
          @click="loadMore"
        >
          <Spinner v-if="loadingMore" :size="14" />
          {{ t('CONVERSATION.OUTSIDER_HISTORY.LOAD_MORE') }}
        </button>
      </template>
    </div>
  </div>
</template>

<style>
/* OUTSIDER: destaque das palavras buscadas dentro do balão (CSS Custom Highlight API,
   não existe utilitário do Tailwind para ::highlight) */
::highlight(outsider-search-hit) {
  background-color: rgb(250 204 21 / 0.75);
  color: rgb(17 24 39);
}
</style>
