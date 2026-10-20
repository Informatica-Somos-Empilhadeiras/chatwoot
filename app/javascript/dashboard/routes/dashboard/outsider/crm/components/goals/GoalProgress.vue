<script setup>
// OUTSIDER: barra de meta: quanto já foi vendido contra a meta do mês. Uma cor só; ao bater a meta
// a barra fica verde e o texto diz "Meta batida". Sem meta, mostra só o vendido.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { attainment, formatMoney } from '../../helpers';

const props = defineProps({
  won: { type: Number, default: 0 },
  goal: { type: Number, default: null },
  large: { type: Boolean, default: false },
});

const { t } = useI18n();

const percent = computed(() => attainment(props.won, props.goal));
const reached = computed(() => percent.value !== null && percent.value >= 100);
const label = computed(() => {
  if (percent.value === null) return t('OUTSIDER_CRM.GOALS.NO_GOAL');
  if (reached.value)
    return t('OUTSIDER_CRM.GOALS.REACHED', { percent: percent.value });
  return t('OUTSIDER_CRM.GOALS.MISSING', {
    percent: percent.value,
    value: formatMoney(props.goal - props.won),
  });
});
</script>

<template>
  <div class="flex flex-col gap-1 min-w-0">
    <div
      class="w-full overflow-hidden rounded-full bg-n-alpha-2"
      :class="large ? 'h-3' : 'h-2'"
      role="progressbar"
      :aria-valuenow="percent ?? 0"
      aria-valuemin="0"
      aria-valuemax="100"
    >
      <div
        v-if="percent !== null"
        class="h-full rounded-full transition-[width]"
        :class="reached ? 'bg-n-teal-9' : 'bg-n-blue-9'"
        :style="{ width: `${Math.min(100, percent)}%` }"
      />
    </div>
    <span
      class="flex items-center gap-1 text-xs tabular-nums"
      :class="reached ? 'text-n-teal-11' : 'text-n-slate-11'"
    >
      <Icon v-if="reached" icon="i-lucide-circle-check" class="size-3.5" />
      {{ label }}
    </span>
  </div>
</template>
