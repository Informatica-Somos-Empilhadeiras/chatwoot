<script setup>
// OUTSIDER: custos das ligações no Painel da Telefonia (Entrega 25; ver app/services/outsider/voice/call_costs.rb):
// o total do período com a comparação com o anterior, o custo médio por ligação cobrada e por minuto, e o
// custo de cada tipo de ligação. Os preços vêm de Telefonia > Configurações > Custos.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import KpiTile from './KpiTile.vue';
import { formatMoney, formatTalkTime } from '../format';

const props = defineProps({
  costs: { type: Object, required: true },
  previousCost: { type: Number, default: null },
});

const { t } = useI18n();

const KINDS = [
  'local_fixed',
  'local_mobile',
  'long_fixed',
  'long_mobile',
  'international',
  'special',
  'inbound',
];

const kinds = computed(() =>
  KINDS.filter(kind => props.costs.by_kind?.[kind]).map(kind => ({
    kind,
    label: t(`OUTSIDER_VOICE.KINDS.${kind.toUpperCase()}`),
    ...props.costs.by_kind[kind],
  }))
);

const maxCost = computed(() =>
  Math.max(0.01, ...kinds.value.map(row => row.cost))
);
const maxCalls = computed(() =>
  Math.max(1, ...kinds.value.map(row => row.calls))
);

const tiles = computed(() => [
  {
    key: 'COST_TOTAL',
    label: t('OUTSIDER_VOICE.WALLBOARD.COSTS.TOTAL'),
    value: formatMoney(props.costs.total),
    icon: 'i-lucide-wallet',
    current: props.costs.total,
    previous: props.previousCost,
    better: 'down',
    hint: t('OUTSIDER_VOICE.WALLBOARD.COSTS.TOTAL_HINT', {
      outbound: formatMoney(props.costs.outbound),
      inbound: formatMoney(props.costs.inbound),
    }),
  },
  {
    key: 'COST_PER_CALL',
    label: t('OUTSIDER_VOICE.WALLBOARD.COSTS.PER_CALL'),
    value: formatMoney(props.costs.per_call),
    icon: 'i-lucide-phone',
    hint: t(
      'OUTSIDER_VOICE.WALLBOARD.COSTS.PER_CALL_HINT',
      props.costs.paid_calls
    ),
  },
  {
    key: 'COST_PER_MINUTE',
    label: t('OUTSIDER_VOICE.WALLBOARD.COSTS.PER_MINUTE'),
    value: formatMoney(props.costs.per_minute, 3),
    icon: 'i-lucide-timer',
    hint: t('OUTSIDER_VOICE.WALLBOARD.COSTS.PER_MINUTE_HINT', {
      billing: t(
        `OUTSIDER_VOICE.SETTINGS.COSTS.BILLINGS.${String(props.costs.billing).toUpperCase()}`
      ),
    }),
  },
]);
</script>

<template>
  <div class="flex flex-col gap-4">
    <p
      v-if="!costs.configured"
      class="flex items-start gap-2 px-3 py-2 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
      data-testid="wallboard-costs-missing"
    >
      <Icon icon="i-lucide-info" class="size-4 mt-0.5 shrink-0" />
      {{ t('OUTSIDER_VOICE.WALLBOARD.COSTS.NOT_CONFIGURED') }}
    </p>
    <div class="grid gap-3 sm:grid-cols-3">
      <KpiTile
        v-for="tile in tiles"
        :key="tile.key"
        v-bind="tile"
        :data-testid="`wallboard-${tile.key.toLowerCase()}`"
      />
    </div>
    <div v-if="kinds.length" class="overflow-x-auto">
      <table class="w-full text-sm" data-testid="wallboard-costs-kinds">
        <thead>
          <tr class="text-xs text-n-slate-11">
            <th class="py-2 font-normal text-left ltr:pr-3 rtl:pl-3">
              {{ t('OUTSIDER_VOICE.SETTINGS.COSTS.KIND') }}
            </th>
            <th class="px-2 py-2 font-normal text-right">
              {{ t('OUTSIDER_VOICE.WALLBOARD.COSTS.CALLS') }}
            </th>
            <th class="px-2 py-2 font-normal text-right">
              {{ t('OUTSIDER_VOICE.WALLBOARD.COSTS.MINUTES') }}
            </th>
            <th class="py-2 font-normal text-right ltr:pl-2 rtl:pr-2 w-1/3">
              {{ t('OUTSIDER_VOICE.WALLBOARD.COSTS.COST') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in kinds"
            :key="row.kind"
            class="border-t border-n-weak"
          >
            <td class="py-2 ltr:pr-3 rtl:pl-3 text-n-slate-12">
              <span class="flex flex-col gap-1">
                {{ row.label }}
                <span class="h-1 rounded-full bg-n-alpha-2">
                  <span
                    class="block h-full rounded-full bg-n-slate-8"
                    :style="{ width: `${(row.calls * 100) / maxCalls}%` }"
                  />
                </span>
              </span>
            </td>
            <td class="px-2 py-2 text-right tabular-nums text-n-slate-12">
              {{ row.calls }}
            </td>
            <td class="px-2 py-2 text-right tabular-nums text-n-slate-12">
              {{ formatTalkTime(row.talk_seconds) }}
            </td>
            <td class="py-2 ltr:pl-2 rtl:pr-2">
              <span class="flex items-center justify-end gap-2">
                <span class="flex-1 h-2 rounded-full bg-n-alpha-2">
                  <span
                    class="block h-full rounded-full bg-n-blue-9"
                    :style="{ width: `${(row.cost * 100) / maxCost}%` }"
                  />
                </span>
                <span
                  class="font-medium text-right w-24 tabular-nums text-n-slate-12"
                >
                  {{ formatMoney(row.cost) }}
                </span>
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
