<script setup>
// OUTSIDER: aba Relatórios do CRM (GET /outsider/crm/reports). Unidade, responsável e período
// valem para a tela toda; o funil mostra um pipeline por vez. Os números seguem as regras dos
// indicadores do Kanban: aberto e ponderado são de agora, ganhos e perdas são do período.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import LoadError from '../../activity/LoadError.vue';
import ForecastChart from './ForecastChart.vue';
import FunnelTable from './FunnelTable.vue';
import BarList from './BarList.vue';
import { errorMessage, formatDate, formatMoney } from '../../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
});

const PERIODS = ['month', 'last_month', 'quarter', 'year', 'last_12_months'];

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const filters = ref({
  business_unit_id: '',
  owner_id: '',
  period: 'month',
  pipeline_id: '',
});
const report = ref(null);
const isLoading = ref(false);
const loadError = ref('');

const managesAnyUnit = computed(
  () =>
    props.access.administrator ||
    props.access.units.some(unit => unit.role === 'manager')
);

// vendedor em alguma unidade: lá os números são só dos negócios dele (o servidor filtra)
const sellerUnits = computed(
  () =>
    !props.access.administrator &&
    props.access.units.some(unit => unit.role === 'seller')
);

const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_UNITS') },
  ...props.units.map(unit => ({ value: unit.id, label: unit.name })),
]);

const ownerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_OWNERS') },
  { value: currentUser.value.id, label: t('OUTSIDER_CRM.FILTERS.MINE') },
  ...(managesAnyUnit.value
    ? agents.value
        .filter(agent => agent.id !== currentUser.value.id)
        .map(agent => ({ value: agent.id, label: agent.name }))
    : []),
]);

const periodOptions = computed(() =>
  PERIODS.map(value => ({
    value,
    label: t(`OUTSIDER_CRM.REPORTS.PERIODS.${value.toUpperCase()}`),
  }))
);

const unitName = id => props.units.find(unit => unit.id === id)?.name;

// com várias unidades à vista, o nome da unidade vem junto do pipeline
const pipelineOptions = computed(() =>
  props.pipelines
    .filter(
      pipeline =>
        pipeline.active &&
        (!filters.value.business_unit_id ||
          pipeline.business_unit_id === filters.value.business_unit_id)
    )
    .map(pipeline => ({
      value: pipeline.id,
      label:
        filters.value.business_unit_id || props.units.length < 2
          ? pipeline.name
          : `${unitName(pipeline.business_unit_id) || ''} · ${pipeline.name}`,
    }))
);

const params = () => {
  const query = { period: filters.value.period };
  ['business_unit_id', 'owner_id', 'pipeline_id'].forEach(key => {
    if (filters.value[key]) query[key] = filters.value[key];
  });
  return query;
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getReport(params());
    report.value = data;
    loadError.value = '';
    // o servidor escolhe o primeiro pipeline quando nenhum foi pedido
    if (data.funnel && filters.value.pipeline_id !== data.funnel.pipeline_id) {
      filters.value.pipeline_id = data.funnel.pipeline_id;
    }
  } catch (error) {
    loadError.value = errorMessage(t, error);
  } finally {
    isLoading.value = false;
  }
};

const summary = computed(() => report.value?.summary);

const days = value =>
  value === null || value === undefined
    ? '—'
    : t('OUTSIDER_CRM.REPORTS.DAYS', { days: String(value).replace('.', ',') });

const percent = value =>
  value === null || value === undefined
    ? '—'
    : `${String(value).replace('.', ',')}%`;

const tiles = computed(() => {
  const data = summary.value;
  if (!data) return [];
  return [
    {
      key: 'OPEN',
      value: formatMoney(data.open_value_cents),
      hint: { count: data.open_count },
    },
    { key: 'WEIGHTED', value: formatMoney(data.weighted_value_cents) },
    {
      key: 'WON',
      value: formatMoney(data.won_value_cents),
      hint: { count: data.won_count },
    },
    {
      key: 'LOST',
      value: formatMoney(data.lost_value_cents),
      hint: { count: data.lost_count },
    },
    {
      key: 'CONVERSION',
      value: percent(data.conversion_rate),
      hint: { won: data.won_count, closed: data.won_count + data.lost_count },
    },
    {
      key: 'TICKET',
      value:
        data.average_ticket_cents === null
          ? '—'
          : formatMoney(data.average_ticket_cents),
    },
    { key: 'DAYS_TO_WIN', value: days(data.average_days_to_win) },
    {
      key: 'FORWARDED',
      value: String(data.forwarded_count),
      hint: { received: data.received_count },
    },
  ];
});

const periodRange = computed(() =>
  report.value
    ? t('OUTSIDER_CRM.REPORTS.PERIOD_RANGE', {
        from: formatDate(report.value.period.from),
        to: formatDate(report.value.period.to),
      })
    : ''
);

const hasData = computed(
  () =>
    summary.value &&
    (summary.value.open_count ||
      summary.value.created_count ||
      summary.value.won_count ||
      summary.value.lost_count ||
      summary.value.forwarded_count)
);

const countValue = (count, cents) =>
  t('OUTSIDER_CRM.REPORTS.COUNT_VALUE', { count, value: formatMoney(cents) });

// trocou a unidade: o servidor escolhe de novo o pipeline
watch(
  () => filters.value.business_unit_id,
  () => {
    filters.value.pipeline_id = '';
    load();
  }
);

watch(() => [filters.value.owner_id, filters.value.period], load);

watch(
  () => filters.value.pipeline_id,
  (value, previous) => {
    if (value && previous && report.value?.funnel?.pipeline_id !== value) {
      load();
    }
  }
);

onMounted(() => {
  store.dispatch('agents/get');
  load();
});
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="flex flex-wrap items-center gap-2">
      <Select
        v-if="units.length > 1"
        v-model="filters.business_unit_id"
        :options="unitOptions"
      />
      <Select v-model="filters.owner_id" :options="ownerOptions" />
      <Select v-model="filters.period" :options="periodOptions" />
      <span v-if="periodRange" class="text-xs text-n-slate-11">
        {{ periodRange }}
      </span>
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
    </div>

    <p
      v-if="sellerUnits"
      class="flex items-center gap-1.5 -mt-2 mb-0 text-xs text-n-slate-11"
    >
      <span class="i-lucide-user-round size-3.5" />
      {{ t('OUTSIDER_CRM.METRICS.OWN_ONLY') }}
    </p>

    <LoadError v-if="loadError" :message="loadError" @retry="load" />

    <div
      v-else-if="!report && isLoading"
      class="flex justify-center p-8 text-n-slate-10"
    >
      <Spinner />
    </div>

    <template v-else-if="report">
      <p
        v-if="!hasData"
        class="p-4 mb-0 text-sm text-center rounded-xl bg-n-alpha-1 text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.REPORTS.EMPTY') }}
      </p>

      <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex flex-col gap-1 p-3 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
        >
          <span class="text-xs text-n-slate-11">
            {{ t(`OUTSIDER_CRM.REPORTS.TILES.${tile.key}`) }}
          </span>
          <span class="text-lg font-semibold truncate text-n-slate-12">
            {{ tile.value }}
          </span>
          <span class="text-xs leading-snug text-n-slate-10">
            {{
              t(`OUTSIDER_CRM.REPORTS.TILES.${tile.key}_HINT`, tile.hint || {})
            }}
          </span>
        </div>
      </div>

      <section
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="flex flex-col gap-0.5">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.TITLE') }}
            </h3>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.SUBTITLE') }}
            </p>
          </div>
          <Select
            v-if="pipelineOptions.length > 1"
            v-model="filters.pipeline_id"
            :options="pipelineOptions"
          />
        </div>
        <template v-if="report.funnel">
          <FunnelTable :funnel="report.funnel" />
          <p class="mb-0 text-xs text-n-slate-11">
            {{
              t('OUTSIDER_CRM.REPORTS.FUNNEL.COHORT', {
                count: report.funnel.cohort_count,
              })
            }}
            <template v-if="report.funnel.truncated">
              · {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.TRUNCATED') }}
            </template>
          </p>
        </template>
        <p v-else class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_CRM.REPORTS.FUNNEL.NO_PIPELINE') }}
        </p>
      </section>

      <section
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <div class="flex flex-col gap-0.5">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.REPORTS.FORECAST.TITLE') }}
          </h3>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.REPORTS.FORECAST.SUBTITLE') }}
          </p>
        </div>
        <ForecastChart :rows="report.forecast" />
      </section>

      <div class="grid gap-5 md:grid-cols-2">
        <section
          v-for="kind in ['lost', 'forward']"
          :key="kind"
          class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
        >
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t(`OUTSIDER_CRM.REPORTS.REASONS.${kind.toUpperCase()}_TITLE`) }}
          </h3>
          <BarList
            :rows="report[`${kind}_reasons`]"
            :empty-label="t('OUTSIDER_CRM.REPORTS.REASONS.EMPTY')"
          />
        </section>
      </div>

      <section
        v-for="table in ['units', 'owners']"
        :key="table"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t(`OUTSIDER_CRM.REPORTS.${table.toUpperCase()}.TITLE`) }}
        </h3>
        <p v-if="!report[table].length" class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_CRM.REPORTS.REASONS.EMPTY') }}
        </p>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm min-w-[40rem]">
            <thead>
              <tr class="text-xs text-left text-n-slate-11">
                <th class="py-2 pr-3 font-normal">
                  {{ t(`OUTSIDER_CRM.REPORTS.${table.toUpperCase()}.NAME`) }}
                </th>
                <th class="py-2 pr-3 font-normal text-right">
                  {{ t('OUTSIDER_CRM.REPORTS.COLUMNS.OPEN') }}
                </th>
                <th class="py-2 pr-3 font-normal text-right">
                  {{ t('OUTSIDER_CRM.REPORTS.COLUMNS.WEIGHTED') }}
                </th>
                <th class="py-2 pr-3 font-normal text-right">
                  {{ t('OUTSIDER_CRM.REPORTS.COLUMNS.WON') }}
                </th>
                <th class="py-2 pr-3 font-normal text-right">
                  {{ t('OUTSIDER_CRM.REPORTS.COLUMNS.LOST') }}
                </th>
                <th
                  v-if="table === 'units'"
                  class="py-2 pr-3 font-normal text-right"
                >
                  {{ t('OUTSIDER_CRM.REPORTS.COLUMNS.FORWARDED') }}
                </th>
                <th
                  v-if="table === 'units'"
                  class="py-2 pr-3 font-normal text-right"
                >
                  {{ t('OUTSIDER_CRM.REPORTS.COLUMNS.RECEIVED') }}
                </th>
                <th class="py-2 font-normal text-right">
                  {{ t('OUTSIDER_CRM.REPORTS.COLUMNS.CONVERSION') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in report[table]"
                :key="row.id || 'none'"
                class="border-t border-n-weak text-n-slate-12"
              >
                <td class="py-2 pr-3">
                  {{ row.name || t('OUTSIDER_CRM.REPORTS.OWNERS.NONE') }}
                </td>
                <td class="py-2 pr-3 text-right tabular-nums">
                  {{ countValue(row.open_count, row.open_value_cents) }}
                </td>
                <td class="py-2 pr-3 text-right tabular-nums">
                  {{ formatMoney(row.weighted_value_cents) }}
                </td>
                <td class="py-2 pr-3 text-right tabular-nums">
                  {{ countValue(row.won_count, row.won_value_cents) }}
                </td>
                <td class="py-2 pr-3 text-right tabular-nums">
                  {{ countValue(row.lost_count, row.lost_value_cents) }}
                </td>
                <td
                  v-if="table === 'units'"
                  class="py-2 pr-3 text-right tabular-nums"
                >
                  {{ row.forwarded_count }}
                </td>
                <td
                  v-if="table === 'units'"
                  class="py-2 pr-3 text-right tabular-nums"
                >
                  {{ row.received_count }}
                </td>
                <td class="py-2 text-right tabular-nums">
                  {{ percent(row.conversion_rate) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>
