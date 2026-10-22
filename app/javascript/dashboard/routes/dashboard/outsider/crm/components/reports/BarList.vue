<script setup>
// OUTSIDER: lista de barras horizontais (motivos de perda e de encaminhamento). Uma cor só: a
// barra mostra a quantidade e o texto ao lado traz quantidade e valor.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatMoney } from '../../helpers';

const props = defineProps({
  rows: { type: Array, required: true },
  emptyLabel: { type: String, required: true },
  tooltipKey: { type: String, default: 'OUTSIDER_CRM.REPORTS.REASONS.TOOLTIP' },
});

const { t } = useI18n();

const max = computed(() => Math.max(1, ...props.rows.map(row => row.count)));
const total = computed(() =>
  props.rows.reduce((sum, row) => sum + row.count, 0)
);

const share = row => Math.round((row.count * 100) / (total.value || 1));
</script>

<template>
  <p v-if="!rows.length" class="mb-0 text-sm text-n-slate-11">
    {{ emptyLabel }}
  </p>
  <ul v-else class="flex flex-col gap-2.5 mb-0 list-none">
    <li
      v-for="row in rows"
      :key="row.id || 'none'"
      v-tooltip="
        t(tooltipKey, {
          count: row.count,
          share: share(row),
          value: formatMoney(row.value_cents),
        })
      "
      class="flex flex-col gap-1"
    >
      <div class="flex items-baseline justify-between gap-3 text-sm">
        <span class="truncate text-n-slate-12">
          {{ row.name || t('OUTSIDER_CRM.REPORTS.REASONS.NONE') }}
        </span>
        <span class="text-xs shrink-0 text-n-slate-11 tabular-nums">
          {{
            t('OUTSIDER_CRM.REPORTS.COUNT_VALUE', {
              count: row.count,
              value: formatMoney(row.value_cents),
            })
          }}
        </span>
      </div>
      <div class="w-full h-2 rounded bg-n-alpha-2">
        <div
          class="h-2 rounded bg-n-blue-9"
          :style="{ width: `${(row.count * 100) / max}%` }"
        />
      </div>
    </li>
  </ul>
</template>
