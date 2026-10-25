<script setup>
// OUTSIDER: barra de meta de ligação (Entrega 22): quanto já fez contra a meta do mês, com um traço onde
// deveria estar hoje (dias úteis já passados). Verde ao bater a meta, azul no ritmo, âmbar abaixo dele.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  value: { type: Number, default: 0 },
  goal: { type: Number, default: null },
  // fração do mês (dias úteis) que já passou, de 0 a 1
  pace: { type: Number, default: 0 },
});

const { t } = useI18n();

const percent = computed(() =>
  props.goal ? Math.round((props.value * 100) / props.goal) : null
);
const expected = computed(() => (props.goal || 0) * props.pace);
const state = computed(() => {
  if (percent.value === null) return null;
  if (percent.value >= 100) return 'REACHED';
  return props.value >= expected.value ? 'ON_PACE' : 'BELOW_PACE';
});
const COLORS = {
  REACHED: { bar: 'bg-n-teal-9', text: 'text-n-teal-11' },
  ON_PACE: { bar: 'bg-n-blue-9', text: 'text-n-blue-11' },
  BELOW_PACE: { bar: 'bg-n-amber-9', text: 'text-n-amber-11' },
};
</script>

<template>
  <div class="flex flex-col gap-1 min-w-0">
    <div
      class="relative w-full h-2 overflow-hidden rounded-full bg-n-alpha-2"
      role="progressbar"
      :aria-valuenow="percent ?? 0"
      aria-valuemin="0"
      aria-valuemax="100"
    >
      <div
        v-if="state"
        class="h-full rounded-full transition-[width]"
        :class="COLORS[state].bar"
        :style="{ width: `${Math.min(100, percent)}%` }"
      />
      <div
        v-if="state && pace > 0 && pace < 1"
        class="absolute inset-y-0 w-0.5 bg-n-slate-12"
        :style="{ left: `${pace * 100}%` }"
      />
    </div>
    <span class="flex flex-wrap items-center gap-x-2 text-xs tabular-nums">
      <span class="text-n-slate-12">
        {{
          state
            ? t('OUTSIDER_VOICE.PANEL.SELLERS.VALUE_OF_GOAL', { value, goal })
            : t('OUTSIDER_VOICE.PANEL.SELLERS.NO_GOAL', { value })
        }}
      </span>
      <span v-if="state" :class="COLORS[state].text">
        {{ t(`OUTSIDER_VOICE.PANEL.SELLERS.${state}`) }}
      </span>
    </span>
  </div>
</template>
