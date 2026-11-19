<script setup>
// OUTSIDER: as OS e os orçamentos de peças e serviços do ERP de um contato (painel da conversa e negócio do CRM). O contato é ligado uma vez
// aos clientes do ERP (empresa + código): sem vínculo, a lista de clientes do ERP já abre, com os parecidos com o
// contato (telefone ou nome) no topo, e filtra por nome, código ou CNPJ (ErpPicker).
// Com "Mostrar ordens de serviço" desligado nas Configurações, o bloco fica só com o vínculo e os orçamentos.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpOrderCard from './ErpOrderCard.vue';
import ErpBudgets from '../budgets/ErpBudgets.vue';
import ErpPicker from './ErpPicker.vue';
import {
  erpState,
  orderKey,
  formatDate,
  withLoadingRetry,
  erpErrorMessage,
} from '../erpStore';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
  opportunityId: { type: Number, default: null },
});

const { t } = useI18n();

const loading = ref(false);
const failure = ref('');
const links = ref([]);
const orders = ref([]);
const options = ref({});
const fetchedAt = ref(null);
const stale = ref(false);
const tab = ref('orders');
const showAll = ref(false);
const searching = ref(false);
const linking = ref('');

const OPEN_LIMIT = 5;
// aba que está na tela: sem OS, sempre orçamentos; sem orçamentos, sempre OS
const activeTab = computed(() => {
  if (!erpState.ordersEnabled) return 'quotes';
  if (!erpState.quotesEnabled) return 'orders';
  return tab.value;
});
const showTabs = computed(
  () => erpState.ordersEnabled && erpState.quotesEnabled
);
const visibleOrders = computed(() =>
  showAll.value ? orders.value : orders.value.slice(0, OPEN_LIMIT)
);

const load = async () => {
  if (!props.contactId) return;
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await withLoadingRetry(() =>
      ErpAPI.contactOrders(props.contactId)
    );
    links.value = data.links || [];
    orders.value = data.orders || [];
    options.value = data.options || {};
    fetchedAt.value = data.fetched_at;
    stale.value = data.stale;
  } catch (error) {
    failure.value = erpErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

watch(
  () => [props.contactId, erpState.enabled],
  () => erpState.enabled && load(),
  { immediate: true }
);

// sem filtro, o servidor põe primeiro os clientes parecidos com este contato
const searchCustomers = async q => {
  const { data } = await withLoadingRetry(() =>
    ErpAPI.customers(q, q ? null : props.contactId)
  );
  return data.customers || [];
};

const customerKey = row => `${row.empresa}:${row.codigo}`;
// "somosemp #716 · GDS · GOIÂNIA/GO · 12.345.678/0001-90"
const customerDetails = row =>
  [
    `${row.empresa} #${row.codigo}`,
    row.fantasia,
    row.cidade && [row.cidade, row.uf].filter(Boolean).join('/'),
    row.documento,
  ]
    .filter(Boolean)
    .join(' · ');

const link = async row => {
  linking.value = customerKey(row);
  try {
    await ErpAPI.link({
      contact_id: props.contactId,
      company: row.empresa,
      code: row.codigo,
      name: row.nome,
    });
    searching.value = false;
    await load();
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    linking.value = '';
  }
};

const unlink = async row => {
  try {
    await ErpAPI.unlink({
      contact_id: props.contactId,
      company: row.empresa,
      code: row.codigo,
    });
    await load();
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  }
};

const updated = order => {
  orders.value = orders.value.map(item =>
    orderKey(item) === orderKey(order) ? order : item
  );
};

const lastUpdate = computed(() =>
  fetchedAt.value
    ? new Date(fetchedAt.value).toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
      })
    : ''
);
</script>

<template>
  <div class="flex flex-col gap-3 text-sm">
    <div v-if="loading && !orders.length" class="flex justify-center p-3">
      <Spinner class="text-n-slate-10" />
    </div>
    <p v-else-if="failure" class="mb-0 text-xs text-n-ruby-11">
      {{ failure }}
      <button type="button" class="underline" @click="load">
        {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
      </button>
    </p>
    <template v-else>
      <!-- clientes do ERP ligados a este contato -->
      <div v-if="links.length" class="flex flex-wrap items-center gap-1.5">
        <span
          v-for="row in links"
          :key="customerKey(row)"
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
          :title="
            t('OUTSIDER_ERP.CONTACT.LINK_TITLE', {
              company: row.empresa,
              code: row.codigo,
            })
          "
        >
          <Icon icon="i-lucide-link" class="size-3 text-n-slate-10" />
          <span class="truncate max-w-40">{{ row.nome || row.codigo }}</span>
          <span class="whitespace-nowrap text-n-slate-10">
            {{ row.empresa }} #{{ row.codigo }}
          </span>
          <button
            v-if="erpState.canEdit || erpState.administrator"
            type="button"
            class="text-n-slate-10 hover:text-n-ruby-11"
            :aria-label="t('OUTSIDER_ERP.CONTACT.UNLINK')"
            @click="unlink(row)"
          >
            <Icon icon="i-lucide-x" class="size-3" />
          </button>
        </span>
        <button
          type="button"
          class="text-xs text-n-blue-11 hover:underline"
          @click="searching = !searching"
        >
          {{ t('OUTSIDER_ERP.CONTACT.ADD_LINK') }}
        </button>
      </div>

      <!-- sem vínculo: a lista de clientes do ERP já aberta -->
      <p v-else class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_ERP.CONTACT.PICK_CUSTOMER') }}
      </p>

      <ErpPicker
        v-if="!links.length || searching"
        :search="searchCustomers"
        :row-key="customerKey"
        :busy="linking"
        :placeholder="t('OUTSIDER_ERP.CONTACT.FILTER_PLACEHOLDER')"
        :empty-text="t('OUTSIDER_ERP.CONTACT.NO_RESULTS')"
        @select="link"
      >
        <template #row="{ row }">
          <span class="text-xs font-medium truncate text-n-slate-12">
            {{ row.nome }}
          </span>
          <span class="text-xs truncate text-n-slate-10">
            {{ customerDetails(row) }}
          </span>
          <span
            v-if="row.motivo"
            class="self-start px-1.5 mt-0.5 text-[11px] rounded bg-n-teal-3 text-n-teal-11"
          >
            {{
              row.motivo === 'telefone'
                ? t('OUTSIDER_ERP.CONTACT.MATCH_PHONE')
                : t('OUTSIDER_ERP.CONTACT.MATCH_NAME')
            }}
          </span>
        </template>
      </ErpPicker>

      <template v-if="links.length">
        <div
          v-if="showTabs"
          class="flex gap-1 p-0.5 rounded-lg bg-n-alpha-1 self-start"
        >
          <button
            v-for="key in ['orders', 'quotes']"
            :key="key"
            type="button"
            class="px-2.5 py-1 text-xs rounded-md"
            :class="
              tab === key
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11'
            "
            @click="tab = key"
          >
            {{ t(`OUTSIDER_ERP.CONTACT.TABS.${key.toUpperCase()}`) }}
            <template v-if="key === 'orders'">({{ orders.length }})</template>
          </button>
        </div>

        <template v-if="activeTab === 'orders'">
          <p v-if="!orders.length" class="mb-0 text-xs text-n-slate-10">
            {{ t('OUTSIDER_ERP.CONTACT.NO_ORDERS') }}
          </p>
          <ErpOrderCard
            v-for="order in visibleOrders"
            :key="orderKey(order)"
            :order="order"
            :options="options[order.Empresa] || []"
            :conversation-id="conversationId"
            @updated="updated"
          />
          <button
            v-if="orders.length > OPEN_LIMIT"
            type="button"
            class="self-start text-xs text-n-blue-11 hover:underline"
            @click="showAll = !showAll"
          >
            {{
              showAll
                ? t('OUTSIDER_ERP.CONTACT.SHOW_LESS')
                : t('OUTSIDER_ERP.CONTACT.SHOW_ALL', { count: orders.length })
            }}
          </button>
        </template>
        <ErpBudgets
          v-else-if="erpState.quotesEnabled"
          :contact-id="contactId"
          :conversation-id="conversationId"
          :opportunity-id="opportunityId"
        />
      </template>

      <span
        v-if="lastUpdate"
        class="flex items-center gap-1 text-xs text-n-slate-10"
        :title="formatDate(fetchedAt)"
      >
        <Icon icon="i-lucide-refresh-cw" class="size-3" />
        {{
          stale
            ? t('OUTSIDER_ERP.CONTACT.STALE', { time: lastUpdate })
            : t('OUTSIDER_ERP.CONTACT.UPDATED', { time: lastUpdate })
        }}
        <button type="button" class="underline" @click="load">
          {{ t('OUTSIDER_ERP.CONTACT.RELOAD') }}
        </button>
      </span>
    </template>
  </div>
</template>
