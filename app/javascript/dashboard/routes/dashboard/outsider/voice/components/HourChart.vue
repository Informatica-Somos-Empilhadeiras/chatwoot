<script setup>
// OUTSIDER: ligações por hora no Painel da Telefonia (Entrega 23; vue-chartjs). Barras empilhadas de
// recebidas, feitas e entre ramais, só nas horas do expediente e nas que tiveram ligação. As cores saem do
// tema e são relidas quando ele muda (claro/escuro).
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

const props = defineProps({
  rows: { type: Array, required: true },
});

ChartJS.register(Tooltip, BarElement, CategoryScale, LinearScale);

const { t } = useI18n();

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

const colors = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  themeVersion.value;
  return {
    inbound: token('--teal-9'),
    outbound: token('--blue-9'),
    internal: token('--slate-8'),
    text: token('--slate-11'),
    grid: token('--slate-6'),
  };
});

const SERIES = ['inbound', 'outbound', 'internal'];

// expediente (8h às 18h) mais as horas que tiveram ligação fora dele
const hours = computed(() => {
  const busy = props.rows
    .filter(row => row.inbound + row.outbound + row.internal > 0)
    .map(row => row.hour);
  const first = Math.min(8, ...busy);
  const last = Math.max(18, ...busy);
  return props.rows.filter(row => row.hour >= first && row.hour <= last);
});

const chartData = computed(() => ({
  labels: hours.value.map(row => `${row.hour}h`),
  datasets: SERIES.map(key => ({
    label: t(`OUTSIDER_VOICE.WALLBOARD.COUNTERS.${key.toUpperCase()}`),
    data: hours.value.map(row => row[key]),
    backgroundColor: colors.value[key],
    hoverBackgroundColor: colors.value[key],
    borderRadius: 3,
    maxBarThickness: 26,
  })),
}));

const options = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 0 },
  interaction: { mode: 'index', intersect: false },
  plugins: { legend: { display: false } },
  scales: {
    x: {
      stacked: true,
      grid: { display: false },
      border: { color: colors.value.grid },
      ticks: { color: colors.value.text },
    },
    y: {
      stacked: true,
      beginAtZero: true,
      border: { display: false },
      grid: { color: colors.value.grid },
      ticks: { color: colors.value.text, precision: 0, maxTicksLimit: 5 },
    },
  },
}));
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-4 text-xs text-n-slate-11">
      <span v-for="key in SERIES" :key="key" class="flex items-center gap-1.5">
        <span
          class="rounded-sm size-2.5"
          :class="{
            'bg-n-teal-9': key === 'inbound',
            'bg-n-blue-9': key === 'outbound',
            'bg-n-slate-8': key === 'internal',
          }"
        />
        {{ t(`OUTSIDER_VOICE.WALLBOARD.COUNTERS.${key.toUpperCase()}`) }}
      </span>
    </div>
    <div class="h-56">
      <Bar :data="chartData" :options="options" />
    </div>
  </div>
</template>
