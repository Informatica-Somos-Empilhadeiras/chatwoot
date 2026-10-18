<script setup>
// OUTSIDER: etiqueta do dia que fica no topo da conversa enquanto se rola
// (o WhatsApp só mostra a data no começo do dia). Mostra o dia da mensagem
// que está no alto da tela e some quando o próprio separador do dia aparece.
// Com a busca aberta (card no alto à direita) o "alto da tela" começa embaixo
// do card e a etiqueta vai para o outro canto; se não couber ao lado do card
// (tela estreita), some enquanto a busca está aberta.
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
const CARD_TRANSITION_MS = 250;

const root = ref(null);
const pillBox = ref(null);
const scroller = ref(null);
const searchCard = ref(null);
const dateKey = ref(null);
const besideSearch = ref(false);
const pillWidths = new Map(); // dia -> largura da etiqueta
let frame = null;
let cardTimer = null;

const visibleSearchCard = () =>
  historyState.searchOpen && searchCard.value?.offsetParent
    ? searchCard.value
    : null;

const fitsBeside = (card, box, key) => {
  const rect = card.getBoundingClientRect();
  const room =
    Math.max(rect.left - box.left, box.right - rect.right) - LIST_INSET_PX;
  return room >= (pillWidths.get(key) || TYPICAL_PILL_PX) + GAP_PX;
};

// guarda a largura da etiqueta mostrada; devolve true se mudou (recalcular o lugar)
const measurePill = () => {
  const pill = pillBox.value?.firstElementChild;
  if (!pill || !dateKey.value) return false;
  if (pillWidths.get(dateKey.value) === pill.offsetWidth) return false;
  pillWidths.set(dateKey.value, pill.offsetWidth);
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
  const blockedBySearch = card && !fitsBeside(card, box, key);
  // sem a busca, no começo da conversa o primeiro separador já está à vista
  const atStart = !card && list.scrollTop < 1;
  const hidden = separatorAtTop || !current || atStart || blockedBySearch;
  dateKey.value = hidden ? null : key;
  besideSearch.value = !!card;
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
        <DayPill :date-key="dateKey" />
      </div>
    </Transition>
  </div>
</template>
