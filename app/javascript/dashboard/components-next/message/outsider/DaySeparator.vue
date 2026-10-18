<script setup>
// OUTSIDER: separador no começo de cada dia da conversa (ver MessageList.vue):
// linha tracejada de lado a lado com a etiqueta do dia no meio.
import DayPill from './DayPill.vue';

defineProps({
  dateKey: { type: String, required: true },
});
</script>

<template>
  <div
    class="relative flex justify-center py-4 pointer-events-none"
    :data-outsider-day="dateKey"
  >
    <div
      aria-hidden="true"
      class="absolute inset-x-0 border-t-2 border-dashed top-1/2 border-n-slate-7"
    />
    <DayPill :date-key="dateKey" class="relative" />
  </div>
</template>
