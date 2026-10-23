<script setup>
// OUTSIDER: criar e editar uma proposta de venda ou locação. Os dados da empresa do cliente vêm do
// contato (ou da última proposta dele) e ficam guardados na proposta; itens do catálogo ou livres;
// condições e textos vêm do modelo. "Ver PDF" salva e mostra o PDF montado na hora. "Enviar" salva e
// manda o PDF por WhatsApp ou e-mail; os envios ficam no histórico. Aceita, recusada ou cancelada fica
// travada até voltar para rascunho.
// Entrega 19: aberta pelo catálogo (?produto=), a proposta nova já vem com o item; o CNPJ preenche os
// dados do cliente (CustomerLookup) e a condição de pagamento sai de uma lista (ProposalConditions).
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
import ProposalItems from './ProposalItems.vue';
import ProposalConditions from './ProposalConditions.vue';
import CustomerLookup from './CustomerLookup.vue';
import ProposalDealLink from './ProposalDealLink.vue';
import ProposalPdfDialog from './ProposalPdfDialog.vue';
import ProposalSendDialog from './ProposalSendDialog.vue';
import ProposalSendHistory from './ProposalSendHistory.vue';
import ConfirmDelete from '../ConfirmDelete.vue';
import { centsToInput, errorMessage, parseMoney } from '../../helpers';
import { withCrmAccess } from '../../crmStore';
import {
  CUSTOMER_FIELDS,
  PROPOSAL_STATUS_COLORS,
  blankItem,
  catalogPrice,
  itemTotal,
  parseQuantity,
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

const kindOptions = computed(() =>
  ['sale', 'rental'].map(kind => ({
    value: kind,
    label: t(`OUTSIDER_CRM.PROPOSALS.KIND.${kind.toUpperCase()}`),
  }))
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

// o que falta para salvar, na ordem em que aparece na tela
const problem = computed(() => {
  const value = form.value;
  if (!value.contact_id) return t('OUTSIDER_CRM.PROPOSALS.ERRORS.CONTACT');
  if (!value.title.trim()) return t('OUTSIDER_CRM.PROPOSALS.ERRORS.TITLE');
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
    Object.assign(form.value, {
      template_id: data.template_id,
      owner_id: data.owner_id,
      issued_on: data.issued_on,
      valid_until: data.valid_until || '',
      customer: { ...data.customer },
      conditions: data.conditions.map(condition => ({ ...condition })),
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
  form.value.title = form.value.title || product.name;
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
    title: value.title.trim(),
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

// próximas situações possíveis a partir da atual
const statusActions = computed(() => {
  const current = proposal.value?.status;
  if (!current || !canEdit.value) return [];
  const map = {
    draft: ['sent', 'canceled'],
    sent: ['accepted', 'rejected', 'canceled'],
    accepted: ['draft'],
    rejected: ['draft'],
    canceled: ['draft'],
  };
  return map[current] || [];
});

const STATUS_ACTION_ICONS = {
  sent: 'i-lucide-send',
  accepted: 'i-lucide-circle-check',
  rejected: 'i-lucide-circle-x',
  canceled: 'i-lucide-ban',
  draft: 'i-lucide-undo-2',
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
  <div v-else class="flex flex-col gap-5">
    <div class="flex flex-wrap items-center gap-2">
      <div class="flex items-center flex-1 min-w-0 gap-2">
        <Button
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-arrow-left"
          :label="t('OUTSIDER_CRM.PROPOSALS.FORM.BACK')"
          @click="close"
        />
        <span class="text-base font-medium truncate text-n-slate-12">
          {{ heading }}
        </span>
        <span
          class="px-2 py-0.5 text-xs rounded-md"
          :class="PROPOSAL_STATUS_COLORS[status]"
        >
          {{ t(`OUTSIDER_CRM.PROPOSALS.STATUS.${status.toUpperCase()}`) }}
        </span>
      </div>
      <div class="flex flex-wrap items-center justify-end gap-2">
        <Button
          v-for="next in statusActions"
          :key="next"
          size="sm"
          variant="faded"
          :color="
            next === 'accepted'
              ? 'teal'
              : next === 'rejected' || next === 'canceled'
                ? 'ruby'
                : 'slate'
          "
          :icon="STATUS_ACTION_ICONS[next]"
          :label="t(`OUTSIDER_CRM.PROPOSALS.ACTIONS.${next.toUpperCase()}`)"
          @click="changeStatus(next)"
        />
        <Button
          v-if="proposal?.can_delete"
          size="sm"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          :label="t('OUTSIDER_CRM.DELETE.CONFIRM')"
          @click="askDelete"
        />
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

    <section v-if="proposal?.sends?.length" class="flex flex-col gap-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{
          t('OUTSIDER_CRM.PROPOSALS.SEND.HISTORY.TITLE', {
            count: proposal.sends.length,
          })
        }}
      </h3>
      <ProposalSendHistory :sends="proposal.sends" />
    </section>

    <section class="flex flex-col gap-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSALS.FORM.SECTION_PROPOSAL') }}
      </h3>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <label class="flex flex-col gap-1 text-xs lg:col-span-2">
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
        <label class="flex flex-col gap-1 text-xs">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.FORM.KIND') }}
          </span>
          <Select
            :model-value="form.kind"
            :options="kindOptions"
            :disabled="!isNew"
            class="!w-full [&>select]:w-full"
            @update:model-value="chooseKind"
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
        <label class="flex flex-col gap-1 text-xs lg:col-span-2">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.FORM.TITLE') }}
          </span>
          <input
            v-model="form.title"
            type="text"
            maxlength="255"
            :disabled="readOnly"
            :placeholder="t('OUTSIDER_CRM.PROPOSALS.FORM.TITLE_PLACEHOLDER')"
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
            {{ t('OUTSIDER_CRM.PROPOSALS.FORM.VALID_UNTIL') }}
          </span>
          <input
            v-model="form.valid_until"
            type="date"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg"
          />
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
    </section>

    <section class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSALS.FORM.SECTION_CUSTOMER') }}
        </h3>
        <CustomerLookup v-model="form.customer" :read-only="readOnly" />
      </div>
      <p class="-mt-2 mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSALS.FORM.CUSTOMER_HELP') }}
      </p>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <label
          v-for="field in CUSTOMER_FIELDS"
          :key="field.key"
          class="flex flex-col gap-1 text-xs"
          :class="{ 'lg:col-span-2': field.wide }"
        >
          <span class="text-n-slate-11">
            {{
              t(`OUTSIDER_CRM.PROPOSALS.CUSTOMER.${field.key.toUpperCase()}`)
            }}
          </span>
          <input
            v-model="form.customer[field.key]"
            type="text"
            maxlength="500"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg"
          />
        </label>
      </div>
    </section>

    <section class="flex flex-col gap-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSALS.FORM.SECTION_ITEMS') }}
      </h3>
      <ProposalItems
        v-model="form.items"
        :kind="form.kind"
        :products="products"
        :read-only="readOnly"
      />
    </section>

    <section class="flex flex-col gap-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSALS.FORM.SECTION_CONDITIONS') }}
      </h3>
      <ProposalConditions
        v-model="form.conditions"
        :payment-options="paymentOptions"
        :read-only="readOnly"
      />
    </section>

    <section class="grid gap-5 lg:grid-cols-2">
      <div class="flex flex-col gap-3">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSALS.FORM.SECTION_SIGNER') }}
        </h3>
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
      <div class="flex flex-col gap-3">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSALS.FORM.NOTES') }}
        </h3>
        <textarea
          v-model="form.notes"
          rows="4"
          maxlength="10000"
          :disabled="readOnly"
          :placeholder="t('OUTSIDER_CRM.PROPOSALS.FORM.NOTES_PLACEHOLDER')"
          class="!mb-0 !text-sm rounded-lg"
        />
      </div>
    </section>

    <div v-if="!readOnly" class="flex flex-wrap items-center justify-end gap-2">
      <span v-if="problem && isDirty" class="text-xs text-n-slate-11">
        {{ problem }}
      </span>
      <Button
        size="sm"
        icon="i-lucide-save"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="!isDirty && !isNew"
        @click="save()"
      />
    </div>

    <ProposalPdfDialog ref="pdfRef" />
    <ProposalSendDialog ref="sendRef" @sent="fromProposal" />
    <ConfirmDelete ref="confirmRef" />
  </div>
</template>
