<script setup>
// OUTSIDER: ligações separadas por DDD do cliente ou por filial no Painel da Telefonia (Entrega 25; ver
// app/services/outsider/voice/call_breakdown.rb): ligações (com a barra em relação à maior), feitas,
// recebidas, atendidas, minutos e custo. Ordena por qualquer coluna.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatMoney, formatTalkTime } from '../format';

const props = defineProps({
  rows: { type: Array, required: true },
  // título da primeira coluna e como mostrar cada linha: { title, subtitle }
  heading: { type: String, required: true },
  label: { type: Function, required: true },
});

const { t } = useI18n();

const COLUMNS = [
  { key: 'calls' },
  { key: 'outbound' },
  { key: 'inbound' },
  { key: 'answered' },
  { key: 'talk_seconds', format: formatTalkTime },
  { key: 'cost', format: value => formatMoney(value) },
];

const sortBy = ref('calls');

const sorted = computed(() =>
  [...props.rows].sort(
    (a, b) => (b[sortBy.value] ?? 0) - (a[sortBy.value] ?? 0)
  )
);
const max = computed(() => Math.max(1, ...props.rows.map(row => row.calls)));
const show = (column, row) =>
  column.format ? column.format(row[column.key]) : row[column.key];
</script>

<template>
  <div class="overflow-x-auto">
    <table class="w-full text-sm">
      <thead>
        <tr class="text-xs text-n-slate-11">
          <th class="py-2 font-normal text-left ltr:pr-3 rtl:pl-3">
            {{ heading }}
          </th>
          <th
            v-for="column in COLUMNS"
            :key="column.key"
            class="px-2 py-2 font-normal text-right whitespace-nowrap"
          >
            <button
              type="button"
              class="inline-flex items-center gap-1 hover:text-n-slate-12"
              :class="{ 'text-n-slate-12 font-medium': sortBy === column.key }"
              @click="sortBy = column.key"
            >
              {{
                t(
                  `OUTSIDER_VOICE.WALLBOARD.BREAKDOWN.${column.key.toUpperCase()}`
                )
              }}
              <Icon
                v-if="sortBy === column.key"
                icon="i-lucide-arrow-down"
                class="size-3"
              />
            </button>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="(row, index) in sorted"
          :key="index"
          class="border-t border-n-weak"
          data-testid="wallboard-breakdown-row"
        >
          <td class="py-2 ltr:pr-3 rtl:pl-3">
            <span class="flex flex-col gap-1 min-w-36">
              <span class="flex items-baseline gap-1.5 min-w-0">
                <span class="truncate text-n-slate-12">
                  {{ label(row).title }}
                </span>
                <span
                  v-if="label(row).subtitle"
                  class="text-xs truncate text-n-slate-11"
                >
                  {{ label(row).subtitle }}
                </span>
              </span>
              <span class="h-1 rounded-full bg-n-alpha-2">
                <span
                  class="block h-full rounded-full bg-n-blue-9"
                  :style="{ width: `${(row.calls * 100) / max}%` }"
                />
              </span>
            </span>
          </td>
          <td
            v-for="column in COLUMNS"
            :key="column.key"
            class="px-2 py-2 text-right tabular-nums text-n-slate-12 whitespace-nowrap"
          >
            {{ show(column, row) }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
