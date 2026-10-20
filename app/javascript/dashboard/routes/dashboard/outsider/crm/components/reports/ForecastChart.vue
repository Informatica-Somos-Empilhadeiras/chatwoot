<script setup>
// OUTSIDER: previsão de fechamento (vue-chartjs). Duas séries do mesmo azul: valor cheio em tom
// claro e ponderado em tom escuro, com legenda em HTML e tooltip com os dois valores e a contagem.
// As cores saem das variáveis do tema e são relidas quando o tema muda (claro/escuro).
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMutationObserver } from '@vueuse/core';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Tooltip,
  BarElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';
import { formatMoney, formatMoneyShort } from '../../helpers';

const props = defineProps({
  rows: { type: Array, required: true },
});

ChartJS.register(Tooltip, BarElement, CategoryScale, LinearScale);

const { t } = useI18n();

const showTable = ref(false);
const themeVersion = ref(0);
useMutationObserver(
  document.documentElement,
  () => {
    themeVersion.value += 1;
  },
  { attributes: true, attributeFilter: ['class'] }
);

const token = name =>
  `rgb(${getComputedStyle(document.documentElement).getPropertyValue(name).trim()})`;

// tons validados contra a superfície de cada tema (claro: 8 e 10; escuro: 7 e 9)
const colors = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  themeVersion.value;
  const dark = document.documentElement.classList.contains('dark');
  return {
    total: token(dark ? '--blue-7' : '--blue-8'),
    weighted: token(dark ? '--blue-9' : '--blue-10'),
    text: token('--slate-11'),
    grid: token('--slate-6'),
    surface: token('--solid-2'),
  };
});

const monthFormat = new Intl.DateTimeFormat('pt-BR', {
  month: 'short',
  year: '2-digit',
});

const label = key => {
  if (key === 'overdue') return t('OUTSIDER_CRM.REPORTS.FORECAST.OVERDUE');
  if (key === 'later') return t('OUTSIDER_CRM.REPORTS.FORECAST.LATER');
  if (key === 'no_date') return t('OUTSIDER_CRM.REPORTS.FORECAST.NO_DATE');
  return monthFormat.format(new Date(`${key}-15T12:00:00`)).replace('.', '');
};

const series = computed(() => [
  {
    key: 'total',
    label: t('OUTSIDER_CRM.REPORTS.FORECAST.TOTAL'),
    color: colors.value.total,
    field: 'value_cents',
  },
  {
    key: 'weighted',
    label: t('OUTSIDER_CRM.REPORTS.FORECAST.WEIGHTED'),
    color: colors.value.weighted,
    field: 'weighted_value_cents',
  },
]);

const chartData = computed(() => ({
  labels: props.rows.map(row => label(row.key)),
  datasets: series.value.map(item => ({
    label: item.label,
    data: props.rows.map(row => row[item.field] / 100),
    backgroundColor: item.color,
    hoverBackgroundColor: item.color,
    borderColor: colors.value.surface,
    borderWidth: { left: 1, right: 1 },
    borderRadius: { topLeft: 4, topRight: 4 },
    borderSkipped: 'bottom',
    maxBarThickness: 28,
  })),
}));

const options = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 0 },
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: { display: false },
    tooltip: {
      callbacks: {
        label: context =>
          `${context.dataset.label}: ${formatMoney(context.raw * 100)}`,
        footer: items =>
          t('OUTSIDER_CRM.REPORTS.FORECAST.TOOLTIP_DEALS', {
            count: props.rows[items[0].dataIndex].count,
          }),
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      border: { color: colors.value.grid },
      ticks: { color: colors.value.text },
    },
    y: {
      beginAtZero: true,
      border: { display: false },
      grid: { color: colors.value.grid },
      ticks: {
        color: colors.value.text,
        maxTicksLimit: 5,
        callback: value => formatMoneyShort(value * 100),
      },
    },
  },
}));
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-4 text-xs text-n-slate-11">
      <span
        v-for="item in series"
        :key="item.key"
        class="flex items-center gap-1.5"
      >
        <span class="rounded-sm size-2.5" :style="{ background: item.color }" />
        {{ item.label }}
      </span>
      <div class="flex-1" />
      <button
        type="button"
        class="text-n-blue-11 hover:underline"
        @click="showTable = !showTable"
      >
        {{
          showTable
            ? t('OUTSIDER_CRM.REPORTS.SHOW_CHART')
            : t('OUTSIDER_CRM.REPORTS.SHOW_TABLE')
        }}
      </button>
    </div>
    <div v-if="!showTable" class="h-64">
      <Bar :data="chartData" :options="options" />
    </div>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-xs text-left text-n-slate-11">
            <th class="py-1.5 pr-3 font-normal">
              {{ t('OUTSIDER_CRM.REPORTS.FORECAST.WHEN') }}
            </th>
            <th class="py-1.5 pr-3 font-normal text-right">
              {{ t('OUTSIDER_CRM.REPORTS.DEALS') }}
            </th>
            <th
              v-for="item in series"
              :key="item.key"
              class="py-1.5 pr-3 font-normal text-right"
            >
              {{ item.label }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.key"
            class="border-t border-n-weak text-n-slate-12"
          >
            <td class="py-1.5 pr-3">{{ label(row.key) }}</td>
            <td class="py-1.5 pr-3 text-right tabular-nums">{{ row.count }}</td>
            <td
              v-for="item in series"
              :key="item.key"
              class="py-1.5 pr-3 text-right tabular-nums"
            >
              {{ formatMoney(row[item.field]) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
