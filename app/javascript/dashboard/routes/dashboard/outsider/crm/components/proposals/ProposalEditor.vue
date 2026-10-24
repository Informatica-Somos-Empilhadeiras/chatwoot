<script setup>
// OUTSIDER: criar e editar uma proposta de venda ou locação. Os dados da empresa do cliente vêm do
// contato (ou da última proposta dele) e ficam guardados na proposta; itens do catálogo ou livres;
// condições e textos vêm do modelo. "Ver PDF" salva e mostra o PDF montado na hora. "Enviar" salva e
// manda o PDF por WhatsApp ou e-mail; os envios ficam no histórico. Aceita, recusada ou cancelada fica
// travada até voltar para rascunho.
// Entrega 19: aberta pelo catálogo (?produto=), a proposta nova já vem com o item; o CNPJ preenche os
// dados do cliente (CustomerLookup) e a condição de pagamento sai de uma lista (PaymentPicker).
// Entrega 20 (mais simples): três passos na ordem em que o vendedor pensa (para quem, o quê, como paga);
// o que é menos usado fica recolhido em "Mais dados do cliente", "Outras condições" e "Mais opções"; o
// título sai do primeiro item quando fica em branco; a barra de baixo mostra o total e os botões de
// salvar e enviar; cancelar e apagar ficam no menu "Mais ações" (ProposalStatusActions).
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import ContactAPI from 'dashboard/api/contacts';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EditorStep from './EditorStep.vue';
import MoreSection from './MoreSection.vue';
import ProposalItems from './ProposalItems.vue';
import ProposalConditions from './ProposalConditions.vue';
import PaymentPicker from './PaymentPicker.vue';
import ProposalStatusActions from './ProposalStatusActions.vue';
import CustomerLookup from './CustomerLookup.vue';
import ProposalDealLink from './ProposalDealLink.vue';
import ProposalPdfDialog from './ProposalPdfDialog.vue';
import ProposalSendDialog from './ProposalSendDialog.vue';
import ProposalSendHistory from './ProposalSendHistory.vue';
import ConfirmDelete from '../ConfirmDelete.vue';
import {
  centsToInput,
  errorMessage,
  formatMoney,
  parseMoney,
} from '../../helpers';
import { withCrmAccess } from '../../crmStore';
import {
  EXTRA_CUSTOMER_FIELDS,
  MAIN_CUSTOMER_FIELDS,
  PROPOSAL_STATUS_COLORS,
  addDays,
  blankItem,
  catalogPrice,
  conditionLabel,
  itemTotal,
  parseQuantity,
  paymentConditionIndex,
  productItemFields,
  quantityToInput,
} from './proposalHelpers';

const props = defineProps({
  proposalId: { type: [String, Number], required: true },
  access: { type: Object, required: true },
  pipelines: { type: Array, required: true },
  // proposta nova aberta do negócio, da conversa ou do catálogo: { contactId, opportunityId, kind, productId }
  initial: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');

const isNew = computed(() => props.proposalId === 'nova');
const proposal = ref(null);
const isLoading = ref(true);
const isSaving = ref(false);
const products = ref([]);
const paymentOptions = ref([]);
const contactOptions = ref([]);
const pdfRef = ref(null);
const sendRef = ref(null);
const confirmRef = ref(null);
const savedSnapshot = ref('');
const showCustomerMore = ref(false);
const showConditions = ref(false);
const showMore = ref(false);

// prazos de validade mais usados, em dias a partir da data da proposta
const VALIDITY_DAYS = [5, 15, 30];

const emptyForm = () => ({
  kind: props.initial.kind === 'rental' ? 'rental' : 'sale',
  template_id: null,
  title: '',
  contact_id: props.initial.contactId || '',
  business_unit_id: '',
  owner_id: null,
  issued_on: '',
  valid_until: '',
  customer: {},
  conditions: [],
  signer: {},
  notes: '',
  items: [],
  link: {
    mode: 'none',
    opportunity_id: '',
    business_unit_id: '',
    pipeline_id: '',
  },
});

const form = ref(emptyForm());

const readOnly = computed(
  () => !isNew.value && !proposal.value?.can_edit_content
);
const canEdit = computed(() => isNew.value || proposal.value?.can_edit);
const isDirty = computed(
  () => JSON.stringify(form.value) !== savedSnapshot.value
);

const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSALS.FORM.NO_UNIT') },
  ...props.access.units.map(unit => ({ value: unit.id, label: unit.name })),
]);

const ownerOptions = computed(() =>
  withCrmAccess(agents.value, form.value.owner_id).map(agent => ({
    value: agent.id,
    label: agent.name,
  }))
);

const status = computed(() =>
  isNew.value ? 'draft' : proposal.value?.display_status || 'draft'
);

const heading = computed(() =>
  isNew.value
    ? t('OUTSIDER_CRM.PROPOSALS.FORM.NEW_TITLE')
    : `${proposal.value?.code || ''} · ${proposal.value?.title || ''}`
);

// título em branco: o nome do primeiro item (o PDF sempre tem título)
const autoTitle = computed(
  () =>
    form.value.items.find(item => item.description.trim())?.description.trim() ||
    t('OUTSIDER_CRM.PROPOSALS.STEPS.DEFAULT_TITLE')
);

const grandTotal = computed(() =>
  form.value.items.reduce((sum, item) => sum + (itemTotal(item) || 0), 0)
);

const extraCustomerSummary = computed(() =>
  t('OUTSIDER_CRM.PROPOSALS.STEPS.MORE_CUSTOMER_SUMMARY', {
    filled: EXTRA_CUSTOMER_FIELDS.filter(key =>
      form.value.customer[key]?.trim()
    ).length,
    total: EXTRA_CUSTOMER_FIELDS.length,
  })
);

// as outras condições (sem a de pagamento, que tem o próprio campo), só os títulos
const otherConditions = computed(() => {
  const payment = paymentConditionIndex(form.value.conditions);
  return form.value.conditions
    .filter((_, index) => index !== payment)
    .map(condition => conditionLabel(condition.label))
    .filter(Boolean);
});

const setValidity = days => {
  form.value.valid_until = addDays(form.value.issued_on, days);
};

// o que falta para salvar, na ordem em que aparece na tela
const problem = computed(() => {
  const value = form.value;
  if (!value.contact_id) return t('OUTSIDER_CRM.PROPOSALS.ERRORS.CONTACT');
  if (!value.customer.company?.trim())
    return t('OUTSIDER_CRM.PROPOSALS.ERRORS.COMPANY');
  if (value.items.some(item => !item.description.trim()))
    return t('OUTSIDER_CRM.PROPOSALS.ERRORS.ITEM_DESCRIPTION');
  if (value.items.some(item => Number.isNaN(itemTotal(item))))
    return t('OUTSIDER_CRM.PROPOSALS.ERRORS.ITEM_VALUES');
  if (value.items.some(item => itemTotal(item) < 0))
    return t('OUTSIDER_CRM.PROPOSALS.ERRORS.ITEM_DISCOUNT');
  if (value.link.mode === 'existing' && !value.link.opportunity_id)
    return t('OUTSIDER_CRM.PROPOSALS.ERRORS.DEAL');
  if (
    value.link.mode === 'create' &&
    (!value.link.business_unit_id || !value.link.pipeline_id)
  )
    return t('OUTSIDER_CRM.PROPOSALS.ERRORS.DEAL_CREATE');
  return '';
});

const markSaved = () => {
  savedSnapshot.value = JSON.stringify(form.value);
};

const itemToForm = item => ({
  id: item.id,
  product_id: item.product_id || '',
  description: item.description,
  quantity: quantityToInput(item.quantity),
  unit_price: centsToInput(item.unit_price_cents),
  discount: centsToInput(item.discount_cents),
  show_details: item.show_details,
  refresh_details: false,
  image_url: item.image_url,
});

const fromProposal = data => {
  proposal.value = data;
  form.value = {
    kind: data.kind,
    template_id: data.template_id,
    title: data.title,
    contact_id: data.contact_id,
    business_unit_id: data.business_unit_id || '',
    owner_id: data.owner_id,
    issued_on: data.issued_on || '',
    valid_until: data.valid_until || '',
    customer: { ...data.customer },
    conditions: data.conditions.map(condition => ({ ...condition })),
    signer: { ...data.signer },
    notes: data.notes || '',
    items: data.items.map(itemToForm),
    link: {
      mode: data.opportunity ? 'existing' : 'none',
      opportunity_id: data.opportunity?.id || '',
      business_unit_id:
        data.business_unit_id || props.access.units[0]?.id || '',
      pipeline_id: '',
    },
  };
  contactOptions.value = [{ value: data.contact.id, label: data.contact.name }];
  markSaved();
};

// dados com que a proposta nova abre: cliente, condições e validade do modelo, assinatura
const applyPrefill = async () => {
  if (!form.value.contact_id) return;
  try {
    const { data } = await CrmAPI.getProposalPrefill({
      contact_id: form.value.contact_id,
      opportunity_id: props.initial.opportunityId || undefined,
      kind: form.value.kind,
    });
    // a condição de pagamento já escolhida continua valendo com as condições do modelo
    const paymentText =
      form.value.conditions[paymentConditionIndex(form.value.conditions)]?.text;
    const conditions = data.conditions.map(condition => ({ ...condition }));
    const paymentIndex = paymentConditionIndex(conditions);
    if (paymentText?.trim() && paymentIndex >= 0) {
      conditions[paymentIndex].text = paymentText;
    } else if (paymentText?.trim()) {
      conditions.unshift({
        label: t('OUTSIDER_CRM.PROPOSALS.PAYMENT.LABEL'),
        text: paymentText,
      });
    }
    Object.assign(form.value, {
      template_id: data.template_id,
      owner_id: data.owner_id,
      issued_on: data.issued_on,
      valid_until: data.valid_until || '',
      customer: { ...data.customer },
      conditions,
      signer: { ...data.signer },
      business_unit_id: data.business_unit_id || '',
    });
    if (data.opportunity_id) {
      form.value.link = {
        ...form.value.link,
        mode: 'existing',
        opportunity_id: data.opportunity_id,
      };
    }
    form.value.link.business_unit_id =
      form.value.link.business_unit_id ||
      data.business_unit_id ||
      props.access.units[0]?.id ||
      '';
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const contactLabel = contact =>
  [contact.name, contact.phone_number || contact.email]
    .filter(Boolean)
    .join(' · ');

const searchContacts = async query => {
  if (!query?.trim()) return;
  try {
    const { data } = await ContactAPI.search(query.trim());
    contactOptions.value = data.payload
      .filter(contact => !String(contact.identifier || '').endsWith('@g.us'))
      .map(contact => ({ value: contact.id, label: contactLabel(contact) }));
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const chooseContact = async contactId => {
  form.value.contact_id = contactId;
  form.value.link = { ...form.value.link, mode: 'none', opportunity_id: '' };
  await applyPrefill();
};

// itens do catálogo que ainda estão com o valor sugerido passam para o valor do outro tipo
const repriceItems = (from, to) => {
  form.value.items.forEach(item => {
    const product = products.value.find(entry => entry.id === item.product_id);
    if (
      !product ||
      item.unit_price !== centsToInput(catalogPrice(product, from))
    ) {
      return;
    }
    item.unit_price = centsToInput(catalogPrice(product, to));
  });
};

const chooseKind = async kind => {
  repriceItems(form.value.kind, kind);
  form.value.kind = kind;
  await applyPrefill();
};

// proposta nova aberta pelo catálogo: o item já entra, e o título começa com o nome dele
const addInitialProduct = () => {
  const product = products.value.find(
    entry => entry.id === props.initial.productId
  );
  if (!product) return;
  form.value.items = [
    { ...blankItem(), ...productItemFields(product, form.value.kind) },
  ];
};

const itemPayload = item => ({
  id: item.id || undefined,
  product_id: item.product_id || null,
  description: item.description.trim(),
  quantity: parseQuantity(item.quantity),
  unit_price_cents: Math.round(parseMoney(item.unit_price) * 100),
  discount_cents: Math.round(parseMoney(item.discount) * 100),
  show_details: item.show_details,
  refresh_details: item.refresh_details || undefined,
});

const payload = () => {
  const value = form.value;
  const data = {
    kind: value.kind,
    template_id: value.template_id || undefined,
    title: value.title.trim() || autoTitle.value,
    business_unit_id: value.business_unit_id || null,
    issued_on: value.issued_on || undefined,
    valid_until: value.valid_until || null,
    customer: value.customer,
    conditions: value.conditions,
    signer: value.signer,
    notes: value.notes,
    items: value.items.map(itemPayload),
  };
  if (isNew.value) data.contact_id = value.contact_id;
  if (props.access.proposals?.assign_owner) data.owner_id = value.owner_id;
  if (value.link.mode === 'existing') {
    data.opportunity_id = value.link.opportunity_id;
  } else if (value.link.mode === 'create') {
    data.create_opportunity = {
      business_unit_id: value.link.business_unit_id,
      pipeline_id: value.link.pipeline_id,
    };
  } else {
    data.opportunity_id = null;
  }
  return data;
};

// devolve a proposta salva (ou null se não deu)
const save = async ({ quiet = false } = {}) => {
  if (problem.value) {
    useAlert(problem.value);
    return null;
  }
  isSaving.value = true;
  try {
    const { data } = isNew.value
      ? await CrmAPI.createProposal(payload())
      : await CrmAPI.updateProposal(proposal.value.id, payload());
    fromProposal(data);
    if (!quiet) useAlert(t('OUTSIDER_CRM.PROPOSALS.FORM.SAVED'));
    if (isNew.value) emit('created', data.id);
    return data;
  } catch (error) {
    useAlert(errorMessage(t, error));
    return null;
  } finally {
    isSaving.value = false;
  }
};

const viewPdf = async () => {
  let current = proposal.value;
  if (isNew.value || (isDirty.value && !readOnly.value)) {
    current = await save({ quiet: true });
  }
  if (current) pdfRef.value?.open(current);
};

const openSend = async () => {
  let current = proposal.value;
  if (isDirty.value && !readOnly.value) current = await save({ quiet: true });
  if (current) sendRef.value?.open(current);
};

const changeStatus = async next => {
  if (isDirty.value && !readOnly.value && !(await save({ quiet: true }))) {
    return;
  }
  try {
    const { data } = await CrmAPI.updateProposalStatus(proposal.value.id, next);
    fromProposal(data);
    useAlert(
      t('OUTSIDER_CRM.PROPOSALS.STATUS_CHANGED', {
        status: t(`OUTSIDER_CRM.PROPOSALS.STATUS.${next.toUpperCase()}`),
      })
    );
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const askDelete = () => {
  confirmRef.value?.open(
    t('OUTSIDER_CRM.PROPOSALS.DELETE.TITLE'),
    t('OUTSIDER_CRM.PROPOSALS.DELETE.TEXT', { code: proposal.value.code }),
    async () => {
      await CrmAPI.deleteProposal(proposal.value.id);
      useAlert(t('OUTSIDER_CRM.PROPOSALS.DELETE.DONE'));
      emit('close');
    }
  );
};

const close = () => {
  // eslint-disable-next-line no-alert
  if (
    isDirty.value &&
    !window.confirm(t('OUTSIDER_CRM.PROPOSALS.FORM.DISCARD'))
  )
    return;
  emit('close');
};

onMounted(async () => {
  if (props.access.proposals?.assign_owner && !agents.value.length) {
    store.dispatch('agents/get');
  }
  try {
    const productRequest = CrmAPI.getProducts();
    const paymentRequest = CrmAPI.getProposalPaymentOptions();
    if (isNew.value) {
      form.value = emptyForm();
      if (form.value.contact_id) {
        const { data } = await ContactAPI.show(form.value.contact_id);
        contactOptions.value = [
          { value: data.payload.id, label: contactLabel(data.payload) },
        ];
        await applyPrefill();
      }
    } else {
      const { data } = await CrmAPI.getProposal(props.proposalId);
      fromProposal(data);
    }
    products.value = (await productRequest).data;
    paymentOptions.value = (await paymentRequest).data.payload;
    if (isNew.value) {
      addInitialProduct();
      markSaved();
    }
  } catch (error) {
    useAlert(errorMessage(t, error));
    emit('close');
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <div v-if="isLoading" class="flex justify-center p-8">
    <Spinner class="text-n-slate-10" />
  </div>
  <div v-else class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <Button
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-arrow-left"
        :label="t('OUTSIDER_CRM.PROPOSALS.FORM.BACK')"
        @click="close"
      />
      <span class="flex-1 min-w-0 text-base font-medium truncate text-n-slate-12">
        {{ heading }}
      </span>
      <span
        class="px-2 py-0.5 text-xs rounded-md"
        :class="PROPOSAL_STATUS_COLORS[status]"
      >
        {{ t(`OUTSIDER_CRM.PROPOSALS.STATUS.${status.toUpperCase()}`) }}
      </span>
      <ProposalStatusActions
        v-if="proposal"
        :status="proposal.status"
        :can-edit="canEdit"
        :can-delete="proposal.can_delete"
        @change="changeStatus"
        @delete="askDelete"
      />
    </div>

    <p
      v-if="readOnly"
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
    >
      {{
        canEdit
          ? t('OUTSIDER_CRM.PROPOSALS.FORM.LOCKED')
          : t('OUTSIDER_CRM.PROPOSALS.FORM.READ_ONLY')
      }}
    </p>

    <MoreSection
      v-if="proposal?.sends?.length"
      :label="
        t('OUTSIDER_CRM.PROPOSALS.SEND.HISTORY.TITLE', {
          count: proposal.sends.length,
        })
      "
    >
      <ProposalSendHistory :sends="proposal.sends" />
    </MoreSection>

    <EditorStep
      :number="1"
      :title="t('OUTSIDER_CRM.PROPOSALS.STEPS.CUSTOMER')"
      :hint="t('OUTSIDER_CRM.PROPOSALS.STEPS.CUSTOMER_HINT')"
    >
      <template #actions>
        <div
          v-if="isNew"
          class="flex p-0.5 rounded-lg bg-n-alpha-2 outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <Button
            v-for="kind in ['sale', 'rental']"
            :key="kind"
            type="button"
            size="sm"
            :variant="form.kind === kind ? 'solid' : 'ghost'"
            :color="form.kind === kind ? 'blue' : 'slate'"
            :label="t(`OUTSIDER_CRM.PROPOSALS.KIND.${kind.toUpperCase()}`)"
            @click="form.kind !== kind && chooseKind(kind)"
          />
        </div>
        <span
          v-else
          class="px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
        >
          {{ t(`OUTSIDER_CRM.PROPOSALS.KIND.${form.kind.toUpperCase()}`) }}
        </span>
      </template>
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="flex flex-col gap-1 text-xs sm:col-span-2">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.FORM.CONTACT') }}
          </span>
          <ComboBox
            :model-value="form.contact_id"
            :options="contactOptions"
            use-api-results
            :disabled="!isNew"
            :placeholder="t('OUTSIDER_CRM.OPPORTUNITY.CONTACT_PLACEHOLDER')"
            :search-placeholder="t('OUTSIDER_CRM.OPPORTUNITY.CONTACT_SEARCH')"
            :empty-state="t('OUTSIDER_CRM.OPPORTUNITY.CONTACT_EMPTY')"
            @search="searchContacts"
            @update:model-value="chooseContact"
          />
        </label>
        <label
          v-for="key in MAIN_CUSTOMER_FIELDS"
          :key="key"
          class="flex flex-col gap-1 text-xs"
        >
          <span class="text-n-slate-11">
            {{ t(`OUTSIDER_CRM.PROPOSALS.CUSTOMER.${key.toUpperCase()}`) }}
          </span>
          <input
            v-model="form.customer[key]"
            type="text"
            maxlength="500"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg"
          />
          <CustomerLookup
            v-if="key === 'document'"
            v-model="form.customer"
            :read-only="readOnly"
          />
        </label>
      </div>
      <MoreSection
        v-model:open="showCustomerMore"
        :label="t('OUTSIDER_CRM.PROPOSALS.STEPS.MORE_CUSTOMER')"
        :summary="extraCustomerSummary"
      >
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <label
            v-for="key in EXTRA_CUSTOMER_FIELDS"
            :key="key"
            class="flex flex-col gap-1 text-xs"
            :class="{ 'sm:col-span-2': key === 'address' }"
          >
            <span class="text-n-slate-11">
              {{ t(`OUTSIDER_CRM.PROPOSALS.CUSTOMER.${key.toUpperCase()}`) }}
            </span>
            <input
              v-model="form.customer[key]"
              type="text"
              maxlength="500"
              :disabled="readOnly"
              class="!mb-0 !text-sm rounded-lg"
            />
          </label>
        </div>
      </MoreSection>
    </EditorStep>

    <EditorStep
      :number="2"
      :title="t('OUTSIDER_CRM.PROPOSALS.STEPS.ITEMS')"
      :hint="t('OUTSIDER_CRM.PROPOSALS.STEPS.ITEMS_HINT')"
    >
      <ProposalItems
        v-model="form.items"
        :kind="form.kind"
        :products="products"
        :read-only="readOnly"
      />
    </EditorStep>

    <EditorStep
      :number="3"
      :title="t('OUTSIDER_CRM.PROPOSALS.STEPS.PAYMENT')"
      :hint="t('OUTSIDER_CRM.PROPOSALS.STEPS.PAYMENT_HINT')"
    >
      <div class="grid gap-4 lg:grid-cols-[1fr_18rem]">
        <div class="flex flex-col gap-1 text-xs">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.PAYMENT.LABEL') }}
          </span>
          <PaymentPicker
            v-model="form.conditions"
            :options="paymentOptions"
            :read-only="readOnly"
          />
        </div>
        <div class="flex flex-col gap-1 text-xs">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.STEPS.VALID_UNTIL') }}
          </span>
          <input
            v-model="form.valid_until"
            type="date"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg"
          />
          <div v-if="!readOnly" class="flex flex-wrap gap-1.5">
            <Button
              v-for="days in VALIDITY_DAYS"
              :key="days"
              type="button"
              size="xs"
              variant="faded"
              color="slate"
              :label="t('OUTSIDER_CRM.PROPOSALS.STEPS.VALID_DAYS', { days })"
              @click="setValidity(days)"
            />
          </div>
        </div>
      </div>
      <MoreSection
        v-model:open="showConditions"
        :label="
          t('OUTSIDER_CRM.PROPOSALS.STEPS.OTHER_CONDITIONS', {
            count: otherConditions.length,
          })
        "
        :summary="otherConditions.slice(0, 4).join(', ')"
      >
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSALS.STEPS.OTHER_CONDITIONS_HINT') }}
        </p>
        <ProposalConditions v-model="form.conditions" :read-only="readOnly" />
      </MoreSection>
    </EditorStep>

    <section
      class="p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container sm:px-5"
    >
      <MoreSection
        v-model:open="showMore"
        :label="t('OUTSIDER_CRM.PROPOSALS.STEPS.MORE')"
        :summary="t('OUTSIDER_CRM.PROPOSALS.STEPS.MORE_SUMMARY')"
      >
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <label class="flex flex-col gap-1 text-xs lg:col-span-2">
            <span class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.PROPOSALS.FORM.TITLE') }}
            </span>
            <input
              v-model="form.title"
              type="text"
              maxlength="255"
              :disabled="readOnly"
              :placeholder="autoTitle"
              class="!mb-0 !text-sm rounded-lg"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs">
            <span class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.PROPOSALS.FORM.ISSUED_ON') }}
            </span>
            <input
              v-model="form.issued_on"
              type="date"
              :disabled="readOnly"
              class="!mb-0 !text-sm rounded-lg"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs">
            <span class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.PROPOSALS.FORM.OWNER') }}
            </span>
            <Select
              v-if="access.proposals?.assign_owner"
              v-model="form.owner_id"
              :options="ownerOptions"
              :disabled="readOnly"
              class="!w-full [&>select]:w-full"
            />
            <span v-else class="flex items-center h-10 text-sm text-n-slate-12">
              {{ proposal?.owner?.name || form.signer.name || '—' }}
            </span>
          </label>
          <label
            v-if="access.units.length"
            class="flex flex-col gap-1 text-xs lg:col-span-2"
          >
            <span class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.PROPOSALS.FORM.UNIT') }}
            </span>
            <Select
              v-model="form.business_unit_id"
              :options="unitOptions"
              :disabled="readOnly"
              class="!w-full [&>select]:w-full"
            />
          </label>
          <div class="flex flex-col gap-1 text-xs lg:col-span-2">
            <span class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.PROPOSALS.FORM.DEAL') }}
            </span>
            <ProposalDealLink
              v-model="form.link"
              :contact-id="form.contact_id"
              :units="access.units"
              :pipelines="pipelines"
              :current="proposal?.opportunity"
              :read-only="readOnly"
            />
          </div>
        </div>
        <div class="grid gap-5 lg:grid-cols-2">
          <div class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_CRM.PROPOSALS.FORM.SECTION_SIGNER') }}
            </span>
            <div class="grid gap-3 sm:grid-cols-2">
              <label
                v-for="key in ['name', 'title', 'phone', 'email']"
                :key="key"
                class="flex flex-col gap-1 text-xs"
              >
                <span class="text-n-slate-11">
                  {{ t(`OUTSIDER_CRM.PROPOSALS.SIGNER.${key.toUpperCase()}`) }}
                </span>
                <input
                  v-model="form.signer[key]"
                  type="text"
                  maxlength="255"
                  :disabled="readOnly"
                  class="!mb-0 !text-sm rounded-lg"
                />
              </label>
            </div>
          </div>
          <label class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_CRM.PROPOSALS.FORM.NOTES') }}
            </span>
            <textarea
              v-model="form.notes"
              rows="4"
              maxlength="10000"
              :disabled="readOnly"
              :placeholder="t('OUTSIDER_CRM.PROPOSALS.FORM.NOTES_PLACEHOLDER')"
              class="!mb-0 !text-sm rounded-lg"
            />
          </label>
        </div>
      </MoreSection>
    </section>

    <div
      class="sticky bottom-0 z-20 flex flex-wrap items-center gap-3 px-4 py-3 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container shadow-lg"
    >
      <div class="flex flex-col">
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSALS.STEPS.TOTAL') }}
        </span>
        <strong class="text-lg tabular-nums text-n-slate-12">
          {{ formatMoney(grandTotal) }}
        </strong>
      </div>
      <span
        v-if="problem && !readOnly && (isDirty || isNew)"
        class="flex-1 min-w-[12rem] text-xs text-n-amber-11"
      >
        {{ problem }}
      </span>
      <span v-else class="flex-1" />
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-file-search"
        :label="t('OUTSIDER_CRM.PROPOSALS.PDF.VIEW')"
        :is-loading="isSaving"
        @click="viewPdf"
      />
      <Button
        v-if="!readOnly"
        size="sm"
        :variant="proposal?.can_send ? 'faded' : 'solid'"
        :color="proposal?.can_send ? 'slate' : 'blue'"
        icon="i-lucide-save"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="!isDirty && !isNew"
        @click="save()"
      />
      <Button
        v-if="proposal?.can_send"
        size="sm"
        icon="i-lucide-send"
        :label="t('OUTSIDER_CRM.PROPOSALS.SEND.OPEN')"
        :is-loading="isSaving"
        @click="openSend"
      />
    </div>

    <ProposalPdfDialog ref="pdfRef" />
    <ProposalSendDialog ref="sendRef" @sent="fromProposal" />
    <ConfirmDelete ref="confirmRef" />
  </div>
</template>
