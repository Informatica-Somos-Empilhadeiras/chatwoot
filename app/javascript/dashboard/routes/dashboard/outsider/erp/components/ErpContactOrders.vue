<script setup>
// OUTSIDER: o ERP de um contato (painel da conversa e negócio do CRM): o vínculo com os clientes do ERP (empresa +
// código) e os orçamentos de peças e serviços (os 5 mais novos e "Ver todos no ERP"). As OS ficam na seção ERP: aqui
// só o atalho "Ver as OS no ERP" com o filtro do contato. Sem vínculo, a lista de clientes do ERP já abre, com os
// parecidos com o contato (telefone ou nome) no topo, e filtra por nome, código ou CNPJ (ErpPicker). Não achou: "Cadastrar
// no ERP" abre o pré-cadastro já com os dados do contato, e o cliente novo fica vinculado a ele. Com a aba Contratos
// aberta no perfil, o bloco "Contratos e máquinas" (ErpContactRentals) vem depois dos orçamentos.
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpBudgets from '../budgets/ErpBudgets.vue';
import ErpPicker from './ErpPicker.vue';
import ErpClientDialog from '../clients/ErpClientDialog.vue';
import ErpContactRentals from '../rentals/ErpContactRentals.vue';
import { erpTabs } from '../sidebar';
import {
  ERP_ROUTE,
  erpState,
  formatDate,
  withLoadingRetry,
  erpErrorMessage,
  companyName,
} from '../erpStore';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
  opportunityId: { type: Number, default: null },
});

const { t } = useI18n();
const route = useRoute();

const loading = ref(false);
const failure = ref('');
const links = ref([]);
const orderCount = ref(0);
const fetchedAt = ref(null);
const stale = ref(false);
const searching = ref(false);
const linking = ref('');
const clientDialog = ref(null);

const showQuotes = computed(() =>
  erpTabs().some(item => item.name === 'orcamentos')
);
const showRentals = computed(() =>
  erpTabs().some(item => item.name === 'contratos')
);
// atalho para as OS dos clientes deste contato na seção ERP (todo o histórico)
const ordersLink = computed(() =>
  erpTabs().some(item => item.name === 'os')
    ? {
        name: ERP_ROUTE,
        params: { accountId: route.params.accountId, tab: 'os' },
        query: { contact: props.contactId },
      }
    : null
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
    orderCount.value = (data.orders || []).length;
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
// "Matriz #716 · GDS · GOIÂNIA/GO · 12.345.678/0001-90"
const customerDetails = row =>
  [
    `${companyName(row.empresa)} #${row.codigo}`,
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

const registerClient = () =>
  clientDialog.value?.open({
    contactId: props.contactId,
    onCreated: async () => {
      searching.value = false;
      await load();
    },
  });

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
    <div v-if="loading && !links.length" class="flex justify-center p-3">
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
              company: companyName(row.empresa),
              code: row.codigo,
            })
          "
        >
          <Icon icon="i-lucide-link" class="size-3 text-n-slate-10" />
          <span class="truncate max-w-40">{{ row.nome || row.codigo }}</span>
          <span class="whitespace-nowrap text-n-slate-10">
            {{ companyName(row.empresa) }} #{{ row.codigo }}
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
      <button
        v-if="erpState.canRegisterClient && (!links.length || searching)"
        type="button"
        class="inline-flex items-center self-start gap-1.5 text-xs font-medium text-n-teal-11 hover:underline"
        @click="registerClient"
      >
        <Icon icon="i-lucide-user-plus" class="size-3.5" />
        {{ t('OUTSIDER_ERP.CLIENT.REGISTER_CONTACT') }}
      </button>
      <ErpClientDialog ref="clientDialog" />

      <template v-if="links.length">
        <ErpBudgets
          v-if="showQuotes"
          :contact-id="contactId"
          :conversation-id="conversationId"
          :opportunity-id="opportunityId"
        />
        <ErpContactRentals v-if="showRentals" :contact-id="contactId" />
        <router-link
          v-if="ordersLink"
          :to="ordersLink"
          class="inline-flex items-center self-start gap-1.5 text-xs font-medium text-n-blue-11 hover:underline"
        >
          <Icon icon="i-lucide-wrench" class="size-3.5" />
          {{
            orderCount
              ? t('OUTSIDER_ERP.CONTACT.ORDERS_IN_ERP_COUNT', {
                  count: orderCount,
                })
              : t('OUTSIDER_ERP.CONTACT.ORDERS_IN_ERP')
          }}
          <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
        </router-link>
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
