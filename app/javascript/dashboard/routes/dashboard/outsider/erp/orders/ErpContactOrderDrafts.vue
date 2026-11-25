<script setup>
// OUTSIDER: bloco "Ordens de serviço feitas no chat" do contato (painel da conversa e negócio do CRM): o botão "Nova OS"
// (Configurações + perfil) e as OS deste contato feitas pelo chat, rascunhos e gravadas, inclusive as conversões de
// orçamento. Rascunho abre a gaveta (ErpOrderDrawer); conversão que ainda não gravou volta para a tela de converter.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpOrderDrawer from './ErpOrderDrawer.vue';
import ErpQuoteConvertDialog from './ErpQuoteConvertDialog.vue';
import { erpState, formatDate, formatMoney, companyName } from '../erpStore';
import {
  draftChip,
  orderDraftsTick,
  orderErrorMessage,
  orderReasonText,
} from './orderHelpers';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const drafts = ref([]);
const loading = ref(false);
const failure = ref('');
const busy = ref('');
const showAll = ref(false);
const drawerRef = ref(null);
const convertRef = ref(null);

const LIMIT = 5;

const load = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await ErpAPI.orderDrafts({ contact_id: props.contactId });
    drafts.value = data.drafts || [];
  } catch (error) {
    failure.value = orderErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, load, { immediate: true });
watch(orderDraftsTick, load);

const visible = computed(() =>
  showAll.value ? drafts.value : drafts.value.slice(0, LIMIT)
);

const upsert = draft => {
  const exists = drafts.value.some(item => item.id === draft.id);
  drafts.value = exists
    ? drafts.value.map(item => (item.id === draft.id ? draft : item))
    : [draft, ...drafts.value];
};

const removed = id => {
  drafts.value = drafts.value.filter(item => item.id !== id);
};

const create = async () => {
  busy.value = 'new';
  try {
    const { data } = await ErpAPI.createOrderDraft({
      kind: 'fresh',
      contact_id: props.contactId,
      conversation_id: props.conversationId || undefined,
    });
    upsert(data.draft);
    drawerRef.value?.open(data.draft, { focus: true });
  } catch (error) {
    useAlert(orderErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

const openDraft = draft => {
  if (draft.kind === 'conversion' && draft.status !== 'created') {
    convertRef.value?.open({
      company: draft.company,
      number: draft.quote_number,
      customerCode: draft.customer_code,
      customerName: draft.customer_name,
      contactId: props.contactId,
      conversationId: props.conversationId,
    });
    return;
  }
  drawerRef.value?.open(draft.id);
};

const rowTitle = draft => {
  if (draft.status === 'created')
    return t('OUTSIDER_ERP.ORDER.CODE', { code: draft.erp_number });
  if (draft.kind === 'conversion')
    return t('OUTSIDER_ERP.ORDER_DRAFT.LIST.CONVERSION', {
      number: draft.quote_number,
    });
  return t('OUTSIDER_ERP.ORDER_DRAFT.LIST.DRAFT');
};

const rowLine = draft =>
  [
    draft.kind === 'conversion' && draft.status === 'created'
      ? t('OUTSIDER_ERP.ORDER_DRAFT.LIST.FROM_QUOTE', {
          number: draft.quote_number,
        })
      : draft.items_count &&
        t('OUTSIDER_ERP.ORDER_DRAFT.LIST.ITEMS', {
          count: draft.items_count,
          total: formatMoney(draft.total),
        }),
    draft.tipo_atendimento,
    formatDate(draft.erp_created_at || draft.updated_at),
  ]
    .filter(Boolean)
    .join(' · ');
</script>

<template>
  <div class="flex flex-col gap-2" data-erp-contact-order-drafts>
    <Button
      v-if="erpState.canCreateOrder"
      size="sm"
      variant="faded"
      color="teal"
      icon="i-lucide-wrench"
      class="w-full"
      :label="t('OUTSIDER_ERP.ORDER_DRAFT.NEW')"
      :is-loading="busy === 'new'"
      data-erp-new-order
      @click="create"
    />
    <div v-if="loading && !drafts.length" class="flex justify-center p-2">
      <Spinner class="size-4 text-n-slate-10" />
    </div>
    <p v-else-if="failure" class="mb-0 text-xs text-n-ruby-11">
      {{ failure }}
      <button type="button" class="underline" @click="load">
        {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
      </button>
    </p>

    <button
      v-for="draft in visible"
      :key="draft.id"
      type="button"
      class="flex flex-col gap-1 p-3 text-sm text-left border rounded-xl bg-n-solid-1 hover:bg-n-alpha-1"
      :class="
        draft.status === 'created'
          ? 'border-n-weak'
          : 'border-dashed border-n-strong'
      "
      @click="openDraft(draft)"
    >
      <span class="flex items-center justify-between w-full gap-2">
        <span class="font-medium truncate text-n-slate-12">
          {{ rowTitle(draft) }}
          <span class="text-xs font-normal text-n-slate-10">
            {{ companyName(draft.company) }}
          </span>
        </span>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full shrink-0"
          :class="draftChip(t, draft).class"
        >
          <Spinner v-if="draftChip(t, draft).spinner" class="size-3" />
          {{ draftChip(t, draft).text }}
        </span>
      </span>
      <span class="text-xs truncate text-n-slate-11">{{ rowLine(draft) }}</span>
      <span
        v-if="draft.customer_name || draft.user"
        class="text-xs truncate text-n-slate-10"
      >
        {{
          [draft.customer_name, draft.user?.name].filter(Boolean).join(' · ')
        }}
      </span>
      <span
        v-if="draft.error && draft.status !== 'created'"
        class="text-xs text-n-ruby-11 line-clamp-2"
      >
        {{ orderReasonText(t, draft.error) }}
      </span>
    </button>

    <button
      v-if="drafts.length > LIMIT"
      type="button"
      class="self-start text-xs text-n-blue-11 hover:underline"
      @click="showAll = !showAll"
    >
      {{
        showAll
          ? t('OUTSIDER_ERP.CONTACT.SHOW_LESS')
          : t('OUTSIDER_ERP.CONTACT.SHOW_ALL', { count: drafts.length })
      }}
    </button>

    <ErpOrderDrawer
      ref="drawerRef"
      :contact-id="contactId"
      @changed="upsert"
      @removed="removed"
    />
    <ErpQuoteConvertDialog ref="convertRef" @converted="upsert" />
  </div>
</template>
