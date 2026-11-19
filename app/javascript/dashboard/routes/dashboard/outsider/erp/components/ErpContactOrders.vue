<script setup>
// OUTSIDER: as OS e os orçamentos do ERP de um contato (painel da conversa e negócio do CRM). O contato é ligado uma vez
// aos clientes do ERP (empresa + código): sem vínculo, aparecem as sugestões pelo nome e a busca de clientes do ERP.
// Com "Mostrar ordens de serviço" desligado nas Configurações, o bloco fica só com o vínculo e os orçamentos.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpOrderCard from './ErpOrderCard.vue';
import ErpQuotes from './ErpQuotes.vue';
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
});

const { t } = useI18n();

const loading = ref(false);
const failure = ref('');
const links = ref([]);
const orders = ref([]);
const suggestions = ref([]);
const options = ref({});
const fetchedAt = ref(null);
const stale = ref(false);
const tab = ref('orders');
const showAll = ref(false);
const searching = ref(false);
const query = ref('');
const results = ref([]);
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
    suggestions.value = data.suggestions || [];
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

const runSearch = debounce(async () => {
  if (query.value.trim().length < 3) {
    results.value = [];
    return;
  }
  try {
    const { data } = await withLoadingRetry(() =>
      ErpAPI.customers(query.value.trim())
    );
    results.value = data.customers || [];
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  }
}, 400);
watch(query, runSearch);

const customerKey = row => `${row.empresa}:${row.codigo}`;

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
    query.value = '';
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

      <!-- sem vínculo: sugestões pelo nome -->
      <div v-else class="flex flex-col gap-2">
        <p class="mb-0 text-xs text-n-slate-11">
          {{
            suggestions.length
              ? t('OUTSIDER_ERP.CONTACT.SUGGESTIONS')
              : t('OUTSIDER_ERP.CONTACT.NO_LINK')
          }}
        </p>
        <div
          v-for="row in suggestions"
          :key="customerKey(row)"
          class="flex items-center justify-between gap-2 p-2 rounded-lg bg-n-alpha-1"
        >
          <div class="flex flex-col min-w-0">
            <span class="text-xs font-medium truncate text-n-slate-12">{{
              row.nome
            }}</span>
            <span class="text-xs text-n-slate-10">
              {{ row.empresa }} #{{ row.codigo }}
              <template v-if="row.cidade">
                · {{ row.cidade }}/{{ row.uf }}
              </template>
              <template v-if="erpState.ordersEnabled">
                ·
                {{
                  t('OUTSIDER_ERP.CONTACT.ORDERS_COUNT', { count: row.count })
                }}
              </template>
            </span>
          </div>
          <Button
            type="button"
            size="xs"
            class="shrink-0"
            :label="t('OUTSIDER_ERP.CONTACT.LINK')"
            :is-loading="linking === customerKey(row)"
            @click="link(row)"
          />
        </div>
        <button
          v-if="!searching"
          type="button"
          class="self-start text-xs text-n-blue-11 hover:underline"
          @click="searching = true"
        >
          {{ t('OUTSIDER_ERP.CONTACT.SEARCH_CUSTOMER') }}
        </button>
      </div>

      <!-- busca de clientes do ERP pelo nome -->
      <div v-if="searching" class="flex flex-col gap-2">
        <input
          v-model="query"
          type="text"
          class="!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
          :placeholder="t('OUTSIDER_ERP.CONTACT.SEARCH_PLACEHOLDER')"
        />
        <div
          v-for="row in results"
          :key="customerKey(row)"
          class="flex items-center justify-between gap-2 p-2 rounded-lg bg-n-alpha-1"
        >
          <div class="flex flex-col min-w-0">
            <span class="text-xs font-medium truncate text-n-slate-12">{{
              row.nome
            }}</span>
            <span class="text-xs text-n-slate-10">
              {{ row.empresa }} #{{ row.codigo }}
              <template v-if="row.cidade">
                · {{ row.cidade }}/{{ row.uf }}
              </template>
              <template v-if="erpState.ordersEnabled">
                ·
                {{
                  t('OUTSIDER_ERP.CONTACT.ORDERS_COUNT', { count: row.count })
                }}
              </template>
            </span>
          </div>
          <Button
            type="button"
            size="xs"
            class="shrink-0"
            :label="t('OUTSIDER_ERP.CONTACT.LINK')"
            :is-loading="linking === customerKey(row)"
            @click="link(row)"
          />
        </div>
        <p
          v-if="query.trim().length >= 3 && !results.length"
          class="mb-0 text-xs text-n-slate-10"
        >
          {{ t('OUTSIDER_ERP.CONTACT.NO_RESULTS') }}
        </p>
      </div>

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
        <ErpQuotes v-else-if="erpState.quotesEnabled" :contact-id="contactId" />
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
