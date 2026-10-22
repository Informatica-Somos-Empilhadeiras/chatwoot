<script setup>
// OUTSIDER: seção "Propostas" da aba Relatórios (Entrega 18, GET /outsider/crm/proposal_reports).
// Usa a unidade, o responsável e o período da aba. Conta as propostas emitidas no período pela
// situação de hoje; vencida = rascunho ou enviada com a validade passada.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/outsider/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import LoadError from '../../activity/LoadError.vue';
import BarList from './BarList.vue';
import { CRM_ROUTE } from '../../sections';
import { errorMessage, formatMoney } from '../../helpers';
import { useCrmChanges } from '../../live';

const props = defineProps({
  filters: { type: Object, required: true },
});

const STATUS_ORDER = ['draft', 'open', 'expired', 'accepted', 'rejected'];

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const report = ref(null);
const isLoading = ref(false);
const loadError = ref('');

const prefix = 'OUTSIDER_CRM.REPORTS.PROPOSALS';

const params = () => {
  const query = { period: props.filters.period };
  ['business_unit_id', 'owner_id'].forEach(key => {
    if (props.filters[key]) query[key] = props.filters[key];
  });
  return query;
};

const load = async options => {
  if (!options?.silent) isLoading.value = true;
  try {
    const { data } = await CrmAPI.getProposalReport(params());
    report.value = data;
    loadError.value = '';
  } catch (error) {
    loadError.value = errorMessage(t, error);
  } finally {
    isLoading.value = false;
  }
};

watch(
  () => [
    props.filters.business_unit_id,
    props.filters.owner_id,
    props.filters.period,
  ],
  () => load(),
  { immediate: true }
);

// proposta ligada a negócio avisa como mudança do negócio
useCrmChanges(changes => {
  if (changes.some(change => change.kind === 'opportunity')) {
    load({ silent: true });
  }
});

const summary = computed(() => report.value?.summary);

const percent = value =>
  value === null || value === undefined
    ? '—'
    : `${String(value).replace('.', ',')}%`;

const days = value =>
  value === null || value === undefined
    ? '—'
    : t('OUTSIDER_CRM.REPORTS.DAYS', { days: String(value).replace('.', ',') });

const tiles = computed(() => {
  const data = summary.value;
  if (!data) return [];
  return [
    {
      key: 'ISSUED',
      value: formatMoney(data.issued_value_cents),
      hint: { count: data.issued_count, sent: data.sent_count },
    },
    {
      key: 'ACCEPTED',
      value: formatMoney(data.accepted_value_cents),
      hint: { count: data.accepted_count },
    },
    { key: 'RATE', value: percent(data.acceptance_rate) },
    { key: 'DAYS', value: days(data.average_days_to_decision) },
  ];
});

const statusName = status =>
  t(
    `OUTSIDER_CRM.PROPOSALS.STATUS.${status === 'open' ? 'SENT' : status.toUpperCase()}`
  );

const statusRows = computed(() =>
  summary.value
    ? STATUS_ORDER.map(status => ({
        id: status,
        name: statusName(status),
        count: summary.value[`${status}_count`],
        value_cents: summary.value[`${status}_value_cents`],
      })).filter(row => row.count)
    : []
);

const countValue = (count, cents) =>
  count
    ? t('OUTSIDER_CRM.REPORTS.COUNT_VALUE', {
        count,
        value: formatMoney(cents),
      })
    : '0';

const quantity = value => String(value).replace('.', ',');

const listRoute = computed(() =>
  accountScopedRoute(CRM_ROUTE, { tab: 'proposals' })
);
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
    data-proposal-report
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex flex-col gap-0.5">
        <h3 class="flex items-center gap-2 text-sm font-medium text-n-slate-12">
          {{ t(`${prefix}.TITLE`) }}
          <Spinner v-if="isLoading" :size="14" class="text-n-slate-10" />
        </h3>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t(`${prefix}.SUBTITLE`) }}
        </p>
      </div>
      <router-link
        :to="listRoute"
        class="text-xs text-n-blue-11 hover:underline"
      >
        {{ t(`${prefix}.OPEN_LIST`) }}
      </router-link>
    </div>

    <LoadError v-if="loadError" :message="loadError" @retry="load" />

    <template v-else-if="summary">
      <p
        v-if="!summary.issued_count"
        class="p-4 mb-0 text-sm text-center rounded-xl bg-n-alpha-1 text-n-slate-11"
      >
        {{ t(`${prefix}.EMPTY`) }}
      </p>

      <template v-else>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div
            v-for="tile in tiles"
            :key="tile.key"
            class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-1"
          >
            <span class="text-xs text-n-slate-11">
              {{ t(`${prefix}.TILES.${tile.key}`) }}
            </span>
            <span class="text-lg font-semibold truncate text-n-slate-12">
              {{ tile.value }}
            </span>
            <span class="text-xs leading-snug text-n-slate-10">
              {{ t(`${prefix}.TILES.${tile.key}_HINT`, tile.hint || {}) }}
            </span>
          </div>
        </div>

        <div class="grid gap-5 md:grid-cols-2">
          <div class="flex flex-col gap-3">
            <h4 class="text-xs font-medium text-n-slate-11">
              {{ t(`${prefix}.STATUS_TITLE`) }}
            </h4>
            <BarList
              :rows="statusRows"
              :empty-label="t(`${prefix}.EMPTY`)"
              :tooltip-key="`${prefix}.TOOLTIP`"
            />
            <p
              v-if="summary.canceled_count"
              class="mb-0 text-xs text-n-slate-10"
            >
              {{
                t(`${prefix}.CANCELED_NOTE`, { count: summary.canceled_count })
              }}
            </p>
          </div>

          <div class="flex flex-col gap-3 min-w-0">
            <h4 class="text-xs font-medium text-n-slate-11">
              {{ t(`${prefix}.PRODUCTS_TITLE`) }}
            </h4>
            <p
              v-if="!report.products.length"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t(`${prefix}.PRODUCTS_EMPTY`) }}
            </p>
            <div v-else class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="text-xs text-left text-n-slate-11">
                    <th class="py-1.5 pr-3 font-normal">
                      {{ t(`${prefix}.COLUMNS.ITEM`) }}
                    </th>
                    <th class="py-1.5 pr-3 font-normal text-right">
                      {{ t(`${prefix}.COLUMNS.QUANTITY`) }}
                    </th>
                    <th class="py-1.5 pr-3 font-normal text-right">
                      {{ t(`${prefix}.COLUMNS.ACCEPTED_QUANTITY`) }}
                    </th>
                    <th class="py-1.5 font-normal text-right">
                      {{ t(`${prefix}.COLUMNS.ACCEPTED_VALUE`) }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="row in report.products"
                    :key="row.product_id || row.name"
                    class="border-t border-n-weak text-n-slate-12"
                  >
                    <td class="py-1.5 pr-3 max-w-[14rem] truncate">
                      {{ row.name }}
                    </td>
                    <td class="py-1.5 pr-3 text-right tabular-nums">
                      {{ quantity(row.quantity) }}
                    </td>
                    <td class="py-1.5 pr-3 text-right tabular-nums">
                      {{ quantity(row.accepted_quantity) }}
                    </td>
                    <td class="py-1.5 text-right tabular-nums">
                      {{ formatMoney(row.accepted_value_cents) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-3">
          <h4 class="text-xs font-medium text-n-slate-11">
            {{ t(`${prefix}.OWNERS_TITLE`) }}
          </h4>
          <div class="overflow-x-auto">
            <table class="w-full text-sm min-w-[40rem]">
              <thead>
                <tr class="text-xs text-left text-n-slate-11">
                  <th class="py-2 pr-3 font-normal">
                    {{ t(`${prefix}.COLUMNS.OWNER`) }}
                  </th>
                  <th
                    v-for="column in [
                      'ISSUED',
                      'OPEN',
                      'ACCEPTED',
                      'REJECTED',
                      'EXPIRED',
                    ]"
                    :key="column"
                    class="py-2 pr-3 font-normal text-right"
                  >
                    {{ t(`${prefix}.COLUMNS.${column}`) }}
                  </th>
                  <th class="py-2 font-normal text-right">
                    {{ t(`${prefix}.COLUMNS.RATE`) }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in report.owners"
                  :key="row.id || 'none'"
                  class="border-t border-n-weak text-n-slate-12"
                >
                  <td class="py-2 pr-3">
                    {{ row.name || t('OUTSIDER_CRM.REPORTS.OWNERS.NONE') }}
                  </td>
                  <td class="py-2 pr-3 text-right tabular-nums">
                    {{ countValue(row.issued_count, row.issued_value_cents) }}
                  </td>
                  <td class="py-2 pr-3 text-right tabular-nums">
                    {{ row.open_count }}
                  </td>
                  <td class="py-2 pr-3 text-right tabular-nums">
                    {{
                      countValue(row.accepted_count, row.accepted_value_cents)
                    }}
                  </td>
                  <td class="py-2 pr-3 text-right tabular-nums">
                    {{ row.rejected_count }}
                  </td>
                  <td class="py-2 pr-3 text-right tabular-nums">
                    {{ row.expired_count }}
                  </td>
                  <td class="py-2 text-right tabular-nums">
                    {{ percent(row.acceptance_rate) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>
    </template>
  </section>
</template>
