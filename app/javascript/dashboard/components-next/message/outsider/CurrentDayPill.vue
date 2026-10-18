<script setup>
// OUTSIDER: etiqueta do dia que fica no topo da conversa enquanto se rola
// (o WhatsApp só mostra a data no começo do dia). Mostra o dia da mensagem
// que está no alto da tela e some quando o próprio separador do dia aparece.
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import DayPill from './DayPill.vue';

const props = defineProps({
  // lista mostrada; só serve para recalcular quando ela muda
  messages: { type: Array, default: () => [] },
});

const SEPARATOR_ZONE_PX = 56;

const root = ref(null);
const dateKey = ref(null);
let scroller = null;
let frame = null;

const update = () => {
  frame = null;
  if (!scroller) return;
  const top = scroller.getBoundingClientRect().top;
  let current = null;
  let separatorAtTop = false;
  scroller.querySelectorAll('[data-outsider-day]').forEach(separator => {
    const rect = separator.getBoundingClientRect();
    if (rect.top < top) current = separator;
    if (rect.bottom > top && rect.top < top + SEPARATOR_ZONE_PX) {
      separatorAtTop = true;
    }
  });
  const hidden = separatorAtTop || !current || scroller.scrollTop < 1;
  dateKey.value = hidden ? null : current.dataset.outsiderDay;
};

const scheduleUpdate = () => {
  if (!frame) frame = requestAnimationFrame(update);
};

onMounted(() => {
  scroller = root.value.parentElement;
  scroller.addEventListener('scroll', scheduleUpdate, { passive: true });
  scheduleUpdate();
});

onBeforeUnmount(() => {
  scroller?.removeEventListener('scroll', scheduleUpdate);
  if (frame) cancelAnimationFrame(frame);
});

watch(
  () => props.messages,
  () => nextTick(scheduleUpdate)
);
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
        :key="dateKey"
        class="absolute inset-x-0 top-0 flex justify-center pt-2"
      >
        <DayPill :date-key="dateKey" />
      </div>
    </Transition>
  </div>
</template>
