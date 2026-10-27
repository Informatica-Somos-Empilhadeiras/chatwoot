<script setup>
// OUTSIDER: como terminaram as ligações do período (Entrega 24): uma barra das recebidas (atendidas e
// perdidas) e uma das feitas (atendeu, não atendeu, ocupado, falhou), cada pedaço do tamanho da sua parte,
// com a quantidade e o % na legenda.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  summary: { type: Object, required: true },
});

const { t } = useI18n();

const ROWS = [
  {
    key: 'INBOUND',
    parts: [
      ['inbound_answered', 'bg-n-teal-9'],
      ['missed', 'bg-n-ruby-9'],
    ],
  },
  {
    key: 'OUTBOUND',
    parts: [
      ['outbound_answered', 'bg-n-blue-9'],
      ['unanswered', 'bg-n-amber-9'],
      ['busy', 'bg-n-slate-9'],
      ['failed', 'bg-n-slate-7'],
    ],
  },
];

const rows = computed(() =>
  ROWS.map(row => {
    const total = row.parts.reduce(
      (sum, [key]) => sum + (props.summary[key] || 0),
      0
    );
    return {
      ...row,
      total,
      parts: row.parts.map(([key, color]) => ({
        key,
        color,
        count: props.summary[key] || 0,
        percent: total
          ? Math.round(((props.summary[key] || 0) * 100) / total)
          : 0,
      })),
    };
  })
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <div v-for="row in rows" :key="row.key" class="flex flex-col gap-2">
      <div class="flex items-baseline justify-between gap-2 text-sm">
        <span class="font-medium text-n-slate-12">
          {{ t(`OUTSIDER_VOICE.WALLBOARD.OUTCOMES.${row.key}`) }}
        </span>
        <span class="text-xs tabular-nums text-n-slate-11">
          {{ row.total }}
        </span>
      </div>
      <div class="flex w-full h-3 gap-0.5 overflow-hidden rounded bg-n-alpha-2">
        <span
          v-for="part in row.parts.filter(item => item.count)"
          :key="part.key"
          class="h-full"
          :class="part.color"
          :style="{ width: `${(part.count * 100) / row.total}%` }"
          :title="`${t(`OUTSIDER_VOICE.WALLBOARD.OUTCOMES.PARTS.${part.key}`)}: ${part.count}`"
        />
      </div>
      <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-n-slate-11">
        <span
          v-for="part in row.parts"
          :key="part.key"
          class="flex items-center gap-1.5"
        >
          <span class="rounded-sm size-2.5" :class="part.color" />
          {{ t(`OUTSIDER_VOICE.WALLBOARD.OUTCOMES.PARTS.${part.key}`) }}
          <span class="font-medium tabular-nums text-n-slate-12">
            {{ part.count }}
          </span>
          <span v-if="row.total" class="tabular-nums">
            ({{ part.percent }}%)
          </span>
        </span>
      </div>
    </div>
  </div>
</template>
