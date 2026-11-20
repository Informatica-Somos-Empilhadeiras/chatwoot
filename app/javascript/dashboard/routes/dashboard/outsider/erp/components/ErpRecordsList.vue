<script setup>
// OUTSIDER: lista paginada de registros do ERP (orcamentos ou pedidos de venda), so visualizacao. Busca por numero ou
// cliente, filtros vindos dos facets do endpoint e paginacao (a nossa camada recorta; o ERP devolve tudo).
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  withLoadingRetry,
  erpErrorMessage,
  formatMoney,
  formatDate,
} from '../erpStore';

const props = defineProps({
  kind: { type: String, required: true }, // 'quotes' | 'sales'
});

const { t } = useI18n();

const CONFIGS = {
  quotes: {
    fetch: params => ErpAPI.quotesList(params),
    columns: [
      { key: 'CodigoOrcamento', label: 'NUMBER' },
      { key: 'Cliente', label: 'CLIENT', grow: true },
      { key: 'Status', label: 'STATUS' },
      { key: 'ValorTotal', label: 'VALUE', money: true },
      { key: 'Vendedor', label: 'SELLER' },
      { key: 'Banco', label: 'COMPANY' },
      { key: 'DataCadastro', label: 'DATE', date: true },
    ],
    filters: [
      { param: 'status', facet: 'statuses', label: 'STATUS' },
      { param: 'company', facet: 'companies', label: 'COMPANY' },
    ],
  },
  sales: {
    fetch: params => ErpAPI.salesOrders(params),
    columns: [
      { key: 'Codigo', label: 'NUMBER' },
      { key: 'Cliente', label: 'CLIENT', grow: true },
      { key: 'Status', label: 'STATUS' },
      { key: 'ValorTotal', label: 'VALUE', money: true },
      { key: 'Vendedor', label: 'SELLER' },
      { key: 'Banco', label: 'COMPANY' },
      { key: 'Emissao', label: 'DATE', date: true },
    ],
    filters: [],
  },
};

const cfg = computed(() => CONFIGS[props.kind] || CONFIGS.quotes);

const loading = ref(true);
const failure = ref('');
const items = ref([]);
const total = ref(0);
const page = ref(1);
const per = ref(30);
const data = ref({});
const fetchedAt = ref(null);
const stale = ref(false);
const query = ref('');
const activeFilters = ref(
  Object.fromEntries(cfg.value.filters.map(f => [f.param, '']))
);

const pages = computed(() => Math.max(1, Math.ceil(total.value / per.value)));

const SELECT =
  '!mb-0 !w-auto h-8 px-2 py-0 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak';

const load = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const params = {
      page: page.value,
      per: per.value,
      q: query.value || undefined,
      ...activeFilters.value,
    };
    const { data: body } = await withLoadingRetry(() => cfg.value.fetch(params));
    items.value = body.items || [];
    total.value = body.total || 0;
    data.value = body;
    fetchedAt.value = body.fetched_at;
    stale.value = body.stale;
  } catch (error) {
    failure.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

const reloadLater = debounce(() => {
  page.value = 1;
  load();
}, 400);
watch(query, reloadLater);
watch(
  activeFilters,
  () => {
    page.value = 1;
    load();
  },
  { deep: true }
);
watch(page, load);
onMounted(load);

const cell = (item, col) => {
  const value = item[col.key];
  if (value === null || value === undefined || value === '') return '-';
  if (col.money) return formatMoney(value);
  if (col.date) return formatDate(value);
  return value;
};

const lastUpdate = () =>
  fetchedAt.value
    ? new Date(fetchedAt.value).toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <div class="relative flex-1 min-w-52 max-w-sm">
        <Icon
          icon="i-lucide-search"
          class="absolute -translate-y-1/2 size-4 left-2 top-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          type="text"
          :class="SELECT"
          class="!w-full !pl-8"
          :placeholder="t('OUTSIDER_ERP.LIST.SEARCH')"
        />
      </div>
      <select
        v-for="f in cfg.filters"
        :key="f.param"
        v-model="activeFilters[f.param]"
        :class="SELECT"
        :aria-label="t(`OUTSIDER_ERP.LIST.${f.label}`)"
      >
        <option value="">
          {{ t('OUTSIDER_ERP.LIST.ALL') }} · {{ t(`OUTSIDER_ERP.LIST.${f.label}`) }}
        </option>
        <option v-for="opt in data[f.facet] || []" :key="opt" :value="opt">
          {{ opt }}
        </option>
      </select>
      <span class="ml-auto text-xs text-n-slate-10">
        {{ t('OUTSIDER_ERP.LIST.TOTAL', { count: total }) }}
        <template v-if="lastUpdate()">
          ·
          {{
            stale
              ? t('OUTSIDER_ERP.CONTACT.STALE', { time: lastUpdate() })
              : t('OUTSIDER_ERP.CONTACT.UPDATED', { time: lastUpdate() })
          }}
        </template>
      </span>
    </div>

    <div v-if="loading && !items.length" class="flex justify-center p-8">
      <Spinner class="text-n-slate-10" />
    </div>
    <p
      v-else-if="failure"
      class="p-4 mb-0 text-sm rounded-xl bg-n-ruby-2 text-n-ruby-11"
    >
      {{ failure }}
    </p>
    <p
      v-else-if="!items.length"
      class="p-6 mb-0 text-sm text-center rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      {{ t('OUTSIDER_ERP.LIST.EMPTY') }}
    </p>
    <div
      v-else
      class="overflow-x-auto"
      :class="loading ? 'opacity-60' : ''"
    >
      <table class="w-full text-sm border-collapse">
        <thead>
          <tr class="text-left border-b border-n-weak text-n-slate-11">
            <th
              v-for="col in cfg.columns"
              :key="col.key"
              class="px-2 py-2 font-medium whitespace-nowrap"
            >
              {{ t(`OUTSIDER_ERP.LIST.${col.label}`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(item, i) in items"
            :key="i"
            class="border-b border-n-weak text-n-slate-12"
          >
            <td
              v-for="col in cfg.columns"
              :key="col.key"
              class="px-2 py-2"
              :class="col.grow ? 'max-w-xs truncate' : 'whitespace-nowrap'"
            >
              {{ cell(item, col) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="items.length" class="flex items-center justify-between gap-2">
      <Button
        type="button"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-chevron-left"
        :label="t('OUTSIDER_ERP.LIST.PREV')"
        :disabled="page <= 1 || loading"
        @click="page -= 1"
      />
      <span class="text-xs text-n-slate-10">
        {{ t('OUTSIDER_ERP.LIST.PAGE_OF', { page, pages }) }}
      </span>
      <Button
        type="button"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-chevron-right"
        :label="t('OUTSIDER_ERP.LIST.NEXT')"
        :disabled="page >= pages || loading"
        @click="page += 1"
      />
    </div>
  </div>
</template>
