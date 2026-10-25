<script setup>
// OUTSIDER: ligações por dia da semana e hora no Painel da Telefonia (Entrega 23): quanto mais ligações,
// mais forte a cor. Segunda a domingo, nas horas do expediente e nas que tiveram ligação.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // [dia da semana (0 = domingo)][hora] = ligações
  grid: { type: Array, required: true },
});

const { t } = useI18n();

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 0];
const SHADES = [
  'bg-n-alpha-1 text-n-slate-10',
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-teal-5 text-n-teal-12',
  'bg-n-teal-7 text-n-teal-12',
  'bg-n-teal-9 text-white',
];

const hours = computed(() => {
  const busy = [];
  props.grid.forEach(row =>
    row.forEach((count, hour) => count && busy.push(hour))
  );
  const first = Math.min(8, ...busy);
  const last = Math.max(18, ...busy);
  return Array.from({ length: last - first + 1 }, (_, index) => first + index);
});

const max = computed(() => Math.max(1, ...props.grid.flat()));

const shade = count =>
  SHADES[count ? Math.min(4, Math.ceil((count / max.value) * 4)) : 0];
</script>

<template>
  <div class="overflow-x-auto">
    <table class="text-xs border-separate border-spacing-1">
      <thead>
        <tr>
          <th />
          <th
            v-for="hour in hours"
            :key="hour"
            class="font-normal text-center text-n-slate-11 min-w-8"
          >
            {{ `${hour}h` }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="day in WEEKDAYS" :key="day">
          <th class="pr-2 font-normal text-left text-n-slate-11">
            {{ t(`OUTSIDER_VOICE.WALLBOARD.WEEKDAYS.${day}`) }}
          </th>
          <td
            v-for="hour in hours"
            :key="hour"
            class="h-7 text-center rounded tabular-nums"
            :class="shade(grid[day][hour])"
          >
            {{ grid[day][hour] || '' }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
