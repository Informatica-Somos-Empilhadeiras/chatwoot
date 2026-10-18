<script setup>
// OUTSIDER: rolagem do histórico da conversa (ver composables/outsider/useConversationHistory.js).
// - carrega mais mensagens para cima e para baixo quando a tela mostra um trecho antigo;
// - botão "Ir para as mais recentes", com quantas mensagens chegaram enquanto se lia o histórico;
// - aviso de carregamento.
// Fica dentro da área da caixa de resposta do MessagesView.vue, logo abaixo da lista.
import { computed, onBeforeUnmount, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  forgetLastJump,
  historyState,
  isNearBottom,
  leaveReadingHistory,
  loadNewer,
  loadOlder,
  newMessagesCount as newCount,
  registerPanel,
  resetHistory,
  returnToLatest,
  setReadingHistory,
} from 'dashboard/composables/outsider/useConversationHistory';

const props = defineProps({
  // o <ul> da lista de mensagens, que é quem rola
  panel: { type: Object, default: null },
  conversationId: { type: Number, required: true },
});

const LOAD_MARGIN_PX = 600;
const USER_SCROLL_WINDOW_MS = 1200;
const USER_INPUT_EVENTS = ['wheel', 'touchmove', 'keydown', 'pointerdown'];

const { t } = useI18n();

let lastUserInput = 0;
let frame = null;

const newCountLabel = computed(() =>
  newCount.value > 99 ? '99+' : String(newCount.value)
);

const showLatestButton = computed(
  () =>
    historyState.conversationId === props.conversationId &&
    (historyState.readingHistory || !!historyState.window)
);

const loadingLabel = computed(() => {
  if (historyState.jumping) return t('CONVERSATION.OUTSIDER_HISTORY.JUMPING');
  if (historyState.loadingOlder) {
    return t('CONVERSATION.OUTSIDER_HISTORY.LOADING_OLDER');
  }
  if (historyState.loadingNewer) {
    return t('CONVERSATION.OUTSIDER_HISTORY.LOADING_NEWER');
  }
  return '';
});

const onFrame = () => {
  frame = null;
  const { panel } = props;
  if (!panel) return;
  if (historyState.window) {
    const distance = panel.scrollHeight - panel.scrollTop - panel.clientHeight;
    if (panel.scrollTop < LOAD_MARGIN_PX) loadOlder();
    if (distance < LOAD_MARGIN_PX) loadNewer();
    return;
  }
  if (isNearBottom()) {
    leaveReadingHistory();
  } else if (performance.now() - lastUserInput < USER_SCROLL_WINDOW_MS) {
    // só rolagem feita pela pessoa conta como "lendo o histórico"
    setReadingHistory(true);
  }
};

const onScroll = () => {
  if (!frame) frame = requestAnimationFrame(onFrame);
};

const markUserInput = () => {
  lastUserInput = performance.now();
  forgetLastJump();
};

const listen = (panel, method) => {
  if (!panel) return;
  panel[method]('scroll', onScroll, { passive: true });
  USER_INPUT_EVENTS.forEach(event =>
    panel[method](event, markUserInput, { passive: true })
  );
};

watch(
  () => props.panel,
  (panel, oldPanel) => {
    listen(oldPanel, 'removeEventListener');
    listen(panel, 'addEventListener');
    registerPanel(panel);
  },
  { immediate: true }
);

watch(
  () => props.conversationId,
  conversationId => resetHistory(conversationId),
  { immediate: true }
);

onBeforeUnmount(() => {
  listen(props.panel, 'removeEventListener');
  registerPanel(null);
  resetHistory(null);
  if (frame) cancelAnimationFrame(frame);
});
</script>

<template>
  <div class="absolute inset-x-0 z-20 h-0 pointer-events-none bottom-full">
    <div
      v-if="loadingLabel"
      class="absolute inset-x-0 flex justify-center bottom-16"
    >
      <div
        class="flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-full shadow-lg bg-n-solid-1 text-n-slate-12 ring-1 ring-n-weak"
      >
        <Spinner :size="16" class="text-n-brand" />
        {{ loadingLabel }}
      </div>
    </div>
    <button
      v-if="showLatestButton"
      type="button"
      class="absolute flex items-center gap-2 px-4 text-sm font-medium rounded-full shadow-lg pointer-events-auto bottom-3 ltr:right-6 rtl:left-6 h-10 bg-n-solid-1 text-n-slate-12 ring-1 ring-n-strong hover:bg-n-solid-2"
      @click="returnToLatest"
    >
      <span
        v-if="newCount"
        class="flex items-center justify-center h-5 px-1.5 text-xs font-semibold text-white rounded-full min-w-5 bg-n-teal-9"
      >
        {{ newCountLabel }}
      </span>
      {{ t('CONVERSATION.OUTSIDER_HISTORY.GO_TO_LATEST') }}
      <span class="i-lucide-arrow-down size-4" />
    </button>
  </div>
</template>
