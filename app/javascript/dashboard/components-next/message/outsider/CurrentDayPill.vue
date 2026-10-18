<script setup>
// OUTSIDER: etiqueta do dia que fica no topo da conversa enquanto se rola
// (o WhatsApp só mostra a data no começo do dia). Mostra o dia da mensagem
// que está no alto da tela e some quando o próprio separador do dia aparece.
// Com a busca aberta (card no alto à direita) o "alto da tela" começa embaixo
// do card e a etiqueta vai para o outro canto; se não couber ao lado do card
// inteira, mostra só "Ontem" ou "qua., 14/10"; sem espaço nem para isso (celular), some.
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useResizeObserver } from '@vueuse/core';
import DayPill from './DayPill.vue';
import { historyState } from 'dashboard/composables/outsider/useConversationHistory';

const props = defineProps({
  // lista mostrada; só serve para recalcular quando ela muda
  messages: { type: Array, default: () => [] },
});

const SEPARATOR_ZONE_PX = 56;
const SEARCH_CARD = '[data-outsider-search-card]';
const LIST_INSET_PX = 16; // px-4 da lista
const GAP_PX = 12;
const TYPICAL_PILL_PX = 300; // até medir a etiqueta de verdade
const TYPICAL_COMPACT_PX = 130; // "qua., 14/10/25"
const CARD_TRANSITION_MS = 250;

const root = ref(null);
const pillBox = ref(null);
const scroller = ref(null);
const searchCard = ref(null);
const dateKey = ref(null);
const besideSearch = ref(false);
const compact = ref(false);
const pillWidths = new Map(); // "dia|full" ou "dia|compact" -> largura da etiqueta
let frame = null;
let cardTimer = null;

const visibleSearchCard = () =>
  historyState.searchOpen && searchCard.value?.offsetParent
    ? searchCard.value
    : null;

// ao lado do card: a etiqueta inteira, a curta ("qua., 14/10") ou nenhuma
const placeBeside = (card, box, key) => {
  const rect = card.getBoundingClientRect();
  const room =
    Math.max(rect.left - box.left, box.right - rect.right) -
    LIST_INSET_PX -
    GAP_PX;
  if (room >= (pillWidths.get(`${key}|full`) || TYPICAL_PILL_PX)) return 'full';
  if (room >= (pillWidths.get(`${key}|compact`) || TYPICAL_COMPACT_PX)) {
    return 'compact';
  }
  return 'none';
};

// guarda a largura da etiqueta mostrada; devolve true se mudou (recalcular o lugar)
const measurePill = () => {
  const pill = pillBox.value?.firstElementChild;
  if (!pill || !dateKey.value) return false;
  const widthKey = `${dateKey.value}|${compact.value ? 'compact' : 'full'}`;
  if (pillWidths.get(widthKey) === pill.offsetWidth) return false;
  pillWidths.set(widthKey, pill.offsetWidth);
  return true;
};

const update = () => {
  frame = null;
  const list = scroller.value;
  if (!list) return;
  const box = list.getBoundingClientRect();
  const card = visibleSearchCard();
  const top =
    box.top +
    (card ? Math.max(0, card.getBoundingClientRect().bottom - box.top) : 0);
  let current = null;
  let separatorAtTop = false;
  list.querySelectorAll('[data-outsider-day]').forEach(separator => {
    if (card) {
      // com o card: o dia só está à vista se a etiqueta dele está inteira abaixo do card
      const label = separator.querySelector('button').getBoundingClientRect();
      if (label.top < top) current = separator;
      else if (label.top < top + SEPARATOR_ZONE_PX) separatorAtTop = true;
      return;
    }
    const rect = separator.getBoundingClientRect();
    if (rect.top < top) current = separator;
    if (rect.bottom > top && rect.top < top + SEPARATOR_ZONE_PX) {
      separatorAtTop = true;
    }
  });
  const key = current?.dataset.outsiderDay;
  const beside = card ? placeBeside(card, box, key) : 'full';
  // sem a busca, no começo da conversa o primeiro separador já está à vista
  const atStart = !card && list.scrollTop < 1;
  const hidden = separatorAtTop || !current || atStart || beside === 'none';
  dateKey.value = hidden ? null : key;
  besideSearch.value = !!card;
  compact.value = beside === 'compact';
  nextTick(() => {
    if (measurePill() && !frame) frame = requestAnimationFrame(update);
  });
};

const scheduleUpdate = () => {
  if (!frame) frame = requestAnimationFrame(update);
};

onMounted(() => {
  scroller.value = root.value.parentElement;
  scroller.value.addEventListener('scroll', scheduleUpdate, { passive: true });
  searchCard.value = document.querySelector(SEARCH_CARD);
  scheduleUpdate();
});

onBeforeUnmount(() => {
  scroller.value?.removeEventListener('scroll', scheduleUpdate);
  if (frame) cancelAnimationFrame(frame);
  clearTimeout(cardTimer);
});

watch(
  () => props.messages,
  () => nextTick(scheduleUpdate)
);

// card da busca abrindo/fechando (e de novo quando a animação termina)
watch(
  () => historyState.searchOpen,
  () => {
    searchCard.value = document.querySelector(SEARCH_CARD);
    nextTick(scheduleUpdate);
    clearTimeout(cardTimer);
    cardTimer = setTimeout(scheduleUpdate, CARD_TRANSITION_MS);
  }
);

// conversa mais estreita (painel do contato aberto) ou card crescendo/recolhendo
useResizeObserver(scroller, scheduleUpdate);
useResizeObserver(searchCard, scheduleUpdate);
</script>

<template>
  <div ref="root" class="sticky top-0 z-10 h-0 pointer-events-none">
    <Transition
      enter-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-150"
      leave-to-class="opacity-0"
    >
      <div
        v-if="dateKey"
        ref="pillBox"
        :key="dateKey"
        class="absolute inset-x-0 top-0 flex pt-2"
        :class="besideSearch ? 'justify-start' : 'justify-center'"
      >
        <DayPill :date-key="dateKey" :compact="compact" />
      </div>
    </Transition>
  </div>
</template>
