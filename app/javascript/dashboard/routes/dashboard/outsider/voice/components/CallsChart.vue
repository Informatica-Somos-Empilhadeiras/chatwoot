<script setup>
// OUTSIDER: barras dos gráficos da Telefonia (Entrega 24; vue-chartjs): uma ou mais séries, empilhadas, com
// a legenda em cima (só com mais de uma série) e o total de cada barra na dica ao passar o mouse.
import { computed } from 'vue';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Tooltip,
  BarElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';
import { SERIES, useChartTheme } from './chartTheme';

const props = defineProps({
  labels: { type: Array, required: true },
  // [{ key, label, data }] (key é uma das cores de chartTheme.js)
  series: { type: Array, required: true },
  // título de cada barra na dica (ex.: "ter 06/10"), no lugar do rótulo do eixo
  titles: { type: Array, default: null },
  // texto do valor na dica (ex.: minutos)
  format: { type: Function, default: value => value },
  height: { type: String, default: 'h-56' },
  totalLabel: { type: String, default: '' },
});

ChartJS.register(Tooltip, BarElement, CategoryScale, LinearScale);

const theme = useChartTheme();

const chartData = computed(() => ({
  labels: props.labels,
  datasets: props.series.map(serie => ({
    label: serie.label,
    data: serie.data,
    backgroundColor: theme.value.color(serie.key),
    hoverBackgroundColor: theme.value.color(serie.key),
    borderColor: theme.value.surface,
    borderWidth: props.series.length > 1 ? { top: 2 } : 0,
    borderSkipped: 'bottom',
    borderRadius: 3,
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
        title: items =>
          props.titles ? props.titles[items[0].dataIndex] : items[0].label,
        label: item => `${item.dataset.label}: ${props.format(item.raw)}`,
        footer: items =>
          props.series.length > 1 && props.totalLabel
            ? `${props.totalLabel}: ${props.format(
                items.reduce((sum, item) => sum + item.raw, 0)
              )}`
            : '',
      },
    },
  },
  scales: {
    x: {
      stacked: true,
      grid: { display: false },
      border: { color: theme.value.grid },
      ticks: { color: theme.value.text, autoSkip: true, maxRotation: 0 },
    },
    y: {
      stacked: true,
      beginAtZero: true,
      border: { display: false },
      grid: { color: theme.value.grid },
      ticks: { color: theme.value.text, precision: 0, maxTicksLimit: 5 },
    },
  },
}));
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-if="series.length > 1"
      class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-n-slate-11"
    >
      <span
        v-for="serie in series"
        :key="serie.key"
        class="flex items-center gap-1.5"
      >
        <span class="rounded-sm size-2.5" :class="SERIES[serie.key].dot" />
        {{ serie.label }}
      </span>
    </div>
    <div :class="height">
      <Bar :data="chartData" :options="options" />
    </div>
  </div>
</template>
