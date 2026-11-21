<script setup>
// OUTSIDER: formulário do rascunho do orçamento de peças e serviços: cliente do ERP (vem do vínculo do contato; "trocar"
// abre a lista de clientes), A/C e pedido do cliente, peças e serviços, condições e totais. Quem salva é a gaveta
// (ErpBudgetDrawer), sozinha, a cada mudança. Cliente que ainda não existe no ERP: "Cadastrar cliente novo" (com a gravação
// de clientes ligada) e o novo já fica escolhido. "locked": o que não muda (edição de um orçamento já gravado: cliente,
// pedido do cliente e as condições que só a função de criar do ERP recebe).
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpPicker from '../components/ErpPicker.vue';
import ErpBudgetItems from './ErpBudgetItems.vue';
import ErpBudgetConditions from './ErpBudgetConditions.vue';
import ErpClientDialog from '../clients/ErpClientDialog.vue';
import { erpState, withLoadingRetry, companyName } from '../erpStore';

const props = defineProps({
  budget: { type: Object, required: true },
  options: { type: Object, default: () => ({}) },
  contactId: { type: Number, default: null },
  readOnly: { type: Boolean, default: false },
  locked: { type: Array, default: () => [] },
});

const emit = defineEmits(['customer']);

const terms = defineModel('terms', { type: Object, default: () => ({}) });
const items = defineModel('items', { type: Array, default: () => [] });

const { t } = useI18n();
const itemsRef = ref(null);
const picking = ref(
  !props.budget.customer_code &&
    !props.readOnly &&
    !props.locked.includes('customer')
);
// cliente de outra unidade com itens já escolhidos: confirma antes (os códigos de produto são de cada unidade)
const pending = ref(null);

const initials = computed(() =>
  String(props.budget.customer_name || '?')
    .split(/\s+/)
    .slice(0, 2)
    .map(word => word[0])
    .join('')
    .toUpperCase()
);

const searchCustomers = async q => {
  const { data } = await withLoadingRetry(() =>
    ErpAPI.customers(q, q ? null : props.contactId)
  );
  return data.customers || [];
};

const apply = (row, clearItems = false) => {
  emit('customer', {
    company: row.empresa,
    customer_code: row.codigo,
    customer_name: row.nome,
    ...(clearItems ? { items: [] } : {}),
  });
  pending.value = null;
  picking.value = false;
};

const choose = row => {
  if (row.empresa !== props.budget.company && items.value.length) {
    pending.value = row;
    return;
  }
  apply(row);
};

const clientDialog = ref(null);
// cliente novo, cadastrado agora no ERP: entra no orçamento como se tivesse sido escolhido na lista
const registerClient = () =>
  clientDialog.value?.open({
    company: props.budget.company,
    contactId: props.contactId,
    onCreated: customer => choose(customer),
  });

const INPUT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand disabled:opacity-70';
const LABEL =
  'flex flex-col gap-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10';

defineExpose({ focusSearch: () => itemsRef.value?.focusSearch() });
</script>

<template>
  <div class="flex flex-col gap-5">
    <div
      class="grid gap-3 md:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)]"
    >
      <div
        class="flex items-center gap-3 px-3 py-2.5 border rounded-xl border-n-weak bg-n-alpha-1"
      >
        <span
          class="flex items-center justify-center text-sm font-semibold rounded-lg shrink-0 size-10 bg-n-teal-3 text-n-teal-11"
        >
          {{ initials }}
        </span>
        <div class="flex flex-col flex-1 min-w-0">
          <span
            v-if="budget.customer_code"
            class="text-sm font-semibold truncate text-n-slate-12"
          >
            {{ budget.customer_code }} · {{ budget.customer_name }}
          </span>
          <span v-else class="text-sm font-medium text-n-amber-11">
            {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.NONE') }}
          </span>
          <span class="text-xs truncate text-n-slate-10">
            {{
              t('OUTSIDER_ERP.BUDGET.CUSTOMER.UNIT', {
                company: budget.company,
              })
            }}
          </span>
        </div>
        <button
          v-if="!readOnly && !locked.includes('customer')"
          type="button"
          class="text-sm font-medium shrink-0 text-n-brand hover:underline"
          @click="picking = !picking"
        >
          {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.CHANGE') }}
        </button>
      </div>
      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.BUDGET.TERMS.CONTATO') }}
        <input
          :value="terms.contato"
          maxlength="50"
          :disabled="readOnly"
          :class="INPUT"
          class="normal-case"
          @input="terms = { ...terms, contato: $event.target.value }"
        />
      </label>
      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.BUDGET.TERMS.PEDIDO_CLIENTE') }}
        <input
          :value="terms.pedido_cliente"
          maxlength="20"
          :disabled="readOnly || locked.includes('pedido_cliente')"
          :placeholder="t('OUTSIDER_ERP.BUDGET.TERMS.OPTIONAL')"
          :class="INPUT"
          class="normal-case"
          @input="terms = { ...terms, pedido_cliente: $event.target.value }"
        />
      </label>
    </div>

    <div v-if="picking" class="flex flex-col gap-2">
      <ErpPicker
        :search="searchCustomers"
        :row-key="row => `${row.empresa}:${row.codigo}`"
        :placeholder="t('OUTSIDER_ERP.CONTACT.FILTER_PLACEHOLDER')"
        :empty-text="t('OUTSIDER_ERP.CONTACT.NO_RESULTS')"
        @select="choose"
      >
        <template #row="{ row }">
          <span class="text-xs font-medium truncate text-n-slate-12">
            {{ row.nome }}
          </span>
          <span class="text-xs truncate text-n-slate-10">
            {{
              [
                `${companyName(row.empresa)} #${row.codigo}`,
                row.fantasia,
                row.cidade && [row.cidade, row.uf].filter(Boolean).join('/'),
                row.documento,
              ]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
        </template>
      </ErpPicker>
      <button
        v-if="erpState.canRegisterClient"
        type="button"
        class="inline-flex items-center self-start gap-1.5 text-xs font-medium text-n-teal-11 hover:underline"
        @click="registerClient"
      >
        <Icon icon="i-lucide-user-plus" class="size-3.5" />
        {{ t('OUTSIDER_ERP.CLIENT.REGISTER_NEW') }}
      </button>
      <ErpClientDialog ref="clientDialog" />
      <div
        v-if="pending"
        class="flex flex-wrap items-center gap-3 p-3 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 shrink-0" />
        <span class="flex-1 min-w-[12rem]">
          {{
            t('OUTSIDER_ERP.BUDGET.CUSTOMER.OTHER_UNIT', {
              company: pending.empresa,
            })
          }}
        </span>
        <button
          type="button"
          class="font-medium underline"
          @click="apply(pending, true)"
        >
          {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.OTHER_UNIT_OK') }}
        </button>
        <button type="button" class="underline" @click="pending = null">
          {{ t('OUTSIDER_ERP.CANCEL') }}
        </button>
      </div>
    </div>

    <section class="flex flex-col gap-2">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h4 class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.BUDGET.ITEMS.TITLE') }}
        </h4>
        <span v-if="!readOnly" class="text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.BUDGET.ITEMS.HINT') }}
        </span>
      </div>
      <ErpBudgetItems
        ref="itemsRef"
        v-model="items"
        :company="budget.company"
        :read-only="readOnly"
        :discount-max="
          options.discount?.enabled ? options.discount.line_max : null
        "
      />
    </section>

    <ErpBudgetConditions
      v-model="terms"
      :items="items"
      :options="options"
      :read-only="readOnly"
      :locked="locked"
    />
  </div>
</template>
