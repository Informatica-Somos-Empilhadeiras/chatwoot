<script setup>
// OUTSIDER: quadro das ordens de serviço do ERP (espelho, só as do período das Configurações). Colunas pelo substatus
// (sem a sigla da filial) ou pela situação do kanban do ERP; filtros por empresa, técnico e busca por OS, cliente,
// máquina ou número de série. Clicar abre a OS no próprio cartão (detalhes e, para quem pode, a edição).
import { ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpOrderCard from './ErpOrderCard.vue';
import { orderKey, withLoadingRetry, erpErrorMessage } from '../erpStore';

const { t } = useI18n();

const loading = ref(true);
const failure = ref('');
const board = ref({ columns: [], companies: [], technicians: [], total: 0 });
const options = ref({});
const filters = ref({
  group_by: 'substatus',
  company: '',
  technician: '',
  q: '',
});
const fetchedAt = ref(null);
const stale = ref(false);

const SELECT =
  '!mb-0 !w-auto h-8 px-2 py-0 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak';

const load = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await withLoadingRetry(() => ErpAPI.board(filters.value));
    board.value = data;
    options.value = data.options || {};
    fetchedAt.value = data.fetched_at;
    stale.value = data.stale;
  } catch (error) {
    failure.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

const reloadLater = debounce(load, 400);
watch(() => filters.value.q, reloadLater);
watch(
  () => [
    filters.value.group_by,
    filters.value.company,
    filters.value.technician,
  ],
  load
);
onMounted(load);

const updated = order => {
  board.value.columns.forEach(column => {
    column.orders = column.orders.map(item =>
      orderKey(item) === orderKey(order) ? order : item
    );
  });
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
          v-model="filters.q"
          type="text"
          :class="SELECT"
          class="!w-full !pl-8"
          :placeholder="t('OUTSIDER_ERP.BOARD.SEARCH')"
        />
      </div>
      <select
        v-model="filters.company"
        :class="SELECT"
        :aria-label="t('OUTSIDER_ERP.BOARD.COMPANY')"
      >
        <option value="">{{ t('OUTSIDER_ERP.BOARD.ALL_COMPANIES') }}</option>
        <option
          v-for="company in board.companies"
          :key="company"
          :value="company"
        >
          {{ company }}
        </option>
      </select>
      <select
        v-model="filters.technician"
        :class="SELECT"
        class="!max-w-56"
        :aria-label="t('OUTSIDER_ERP.BOARD.TECHNICIAN')"
      >
        <option value="">{{ t('OUTSIDER_ERP.BOARD.ALL_TECHNICIANS') }}</option>
        <option v-for="name in board.technicians" :key="name" :value="name">
          {{ name }}
        </option>
      </select>
      <select
        v-model="filters.group_by"
        :class="SELECT"
        :aria-label="t('OUTSIDER_ERP.BOARD.GROUP_BY')"
      >
        <option value="substatus">
          {{ t('OUTSIDER_ERP.BOARD.BY_SUBSTATUS') }}
        </option>
        <option value="status">{{ t('OUTSIDER_ERP.BOARD.BY_STATUS') }}</option>
      </select>
      <span class="ml-auto text-xs text-n-slate-10">
        {{ t('OUTSIDER_ERP.BOARD.TOTAL', { count: board.total }) }}
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

    <div
      v-if="loading && !board.columns.length"
      class="flex justify-center p-8"
    >
      <Spinner class="text-n-slate-10" />
    </div>
    <p
      v-else-if="failure"
      class="p-4 mb-0 text-sm rounded-xl bg-n-ruby-2 text-n-ruby-11"
    >
      {{ failure }}
    </p>
    <p
      v-else-if="!board.columns.length"
      class="p-6 mb-0 text-sm text-center rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      {{ t('OUTSIDER_ERP.BOARD.EMPTY') }}
    </p>
    <div
      v-else
      class="flex gap-3 pb-3 overflow-x-auto"
      :class="loading ? 'opacity-60' : ''"
    >
      <section
        v-for="column in board.columns"
        :key="column.name"
        class="flex flex-col gap-2 p-2 rounded-xl bg-n-alpha-1 w-80 shrink-0 max-h-[calc(100vh-14rem)]"
      >
        <header class="flex items-center justify-between px-1 pt-1">
          <span class="text-sm font-medium truncate text-n-slate-12">{{
            column.name
          }}</span>
          <span class="px-2 text-xs rounded-full bg-n-alpha-2 text-n-slate-11">
            {{ column.count }}
          </span>
        </header>
        <div class="flex flex-col gap-2 overflow-y-auto">
          <ErpOrderCard
            v-for="order in column.orders"
            :key="orderKey(order)"
            :order="order"
            :options="options[order.Empresa] || []"
            @updated="updated"
          />
          <p
            v-if="column.count > column.orders.length"
            class="px-1 mb-0 text-xs text-n-slate-10"
          >
            {{
              t('OUTSIDER_ERP.BOARD.MORE', {
                count: column.count - column.orders.length,
              })
            }}
          </p>
        </div>
      </section>
    </div>
  </div>
</template>
