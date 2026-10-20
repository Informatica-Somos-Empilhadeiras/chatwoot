<script setup>
// OUTSIDER: indicadores do topo (GET /opportunities/summary) com os mesmos filtros da tela.
// Em aberto e previsão contam os negócios abertos; ganhos, conversão e tempo médio contam
// os fechados no período escolhido. Nas unidades em que a pessoa é só vendedor, o servidor conta
// só os negócios dela (ownOnly mostra o aviso).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import { errorMessage, formatMoney } from '../helpers';

const props = defineProps({
  filters: { type: Object, required: true },
  refreshKey: { type: Number, default: 0 },
  ownOnly: { type: Boolean, default: false },
});

const { t } = useI18n();

const summary = ref(null);

const cards = computed(() => {
  const data = summary.value;
  if (!data) return [];
  const closed = data.won_count + data.lost_count;
  return [
    {
      key: 'OPEN',
      value: formatMoney(data.open_value_cents),
      hint: t('OUTSIDER_CRM.METRICS.DEALS', { count: data.open_count }),
    },
    {
      key: 'WEIGHTED',
      value: formatMoney(data.weighted_value_cents),
      hint: t('OUTSIDER_CRM.METRICS.WEIGHTED_HINT'),
    },
    {
      key: 'WON',
      value: formatMoney(data.won_value_cents),
      hint: t('OUTSIDER_CRM.METRICS.DEALS', { count: data.won_count }),
    },
    {
      key: 'CONVERSION',
      value: data.conversion_rate === null ? '—' : `${data.conversion_rate}%`,
      hint: t('OUTSIDER_CRM.METRICS.CONVERSION_HINT', {
        won: data.won_count,
        closed,
      }),
    },
    {
      key: 'AVERAGE_DAYS',
      value:
        data.average_days_to_win === null
          ? '—'
          : t('OUTSIDER_CRM.METRICS.DAYS', {
              days: String(data.average_days_to_win).replace('.', ','),
            }),
      hint: t('OUTSIDER_CRM.METRICS.AVERAGE_DAYS_HINT'),
    },
  ];
});

const load = async () => {
  const params = { period: props.filters.period || 'month' };
  ['business_unit_id', 'pipeline_id', 'owner_id', 'q'].forEach(key => {
    if (props.filters[key]) params[key] = props.filters[key];
  });
  try {
    const { data } = await CrmAPI.getSummary(params);
    summary.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

watch(
  () => [
    props.filters.period,
    props.refreshKey,
    props.filters.business_unit_id,
    props.filters.pipeline_id,
    props.filters.owner_id,
    props.filters.q,
  ],
  load,
  { immediate: true }
);
</script>

<template>
  <p
    v-if="ownOnly"
    class="flex items-center gap-1.5 -mb-1 text-xs text-n-slate-11"
  >
    <span class="i-lucide-user-round size-3.5" />
    {{ t('OUTSIDER_CRM.METRICS.OWN_ONLY') }}
  </p>
  <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
    <div
      v-for="card in cards"
      :key="card.key"
      class="flex flex-col gap-1 p-3 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
    >
      <span class="text-xs text-n-slate-11">
        {{ t(`OUTSIDER_CRM.METRICS.${card.key}`) }}
      </span>
      <span class="text-lg font-semibold truncate text-n-slate-12">
        {{ card.value }}
      </span>
      <span class="text-xs truncate text-n-slate-10">{{ card.hint }}</span>
    </div>
  </div>
</template>
