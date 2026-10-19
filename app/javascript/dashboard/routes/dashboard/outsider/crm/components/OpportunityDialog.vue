<script setup>
// OUTSIDER: criar e editar oportunidade. O contato vem do Chatwoot (busca nos contatos da
// conta); unidade e pipeline só se escolhem na criação, porque trocar de unidade é encaminhamento.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import ContactAPI from 'dashboard/api/contacts';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import CustomFieldInput from './CustomFieldInput.vue';
import { centsToInput, errorMessage, parseMoney } from '../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  pipelines: { type: Array, required: true },
  agents: { type: Array, required: true },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');

const dialogRef = ref(null);
const isSaving = ref(false);
const editing = ref(null);
const contactOptions = ref([]);
const customFields = ref([]);
const lostReasons = ref([]);

const emptyForm = () => ({
  contact_id: '',
  business_unit_id: props.access.units[0]?.id ?? '',
  pipeline_id: '',
  stage_id: '',
  title: '',
  value: '',
  expected_close_on: '',
  probability: '',
  owner_id: currentUser.value.id,
  status: 'open',
  lost_reason_id: '',
  custom_fields: {},
});

const form = ref(emptyForm());

const unitOptions = computed(() =>
  props.access.units.map(unit => ({ value: unit.id, label: unit.name }))
);

const unitPipelines = computed(() =>
  props.pipelines.filter(
    pipeline =>
      pipeline.business_unit_id === form.value.business_unit_id &&
      (pipeline.active || pipeline.id === form.value.pipeline_id)
  )
);

const pipelineOptions = computed(() =>
  unitPipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);

const currentPipeline = computed(() =>
  props.pipelines.find(pipeline => pipeline.id === form.value.pipeline_id)
);

const stageOptions = computed(() =>
  (currentPipeline.value?.stages || []).map(stage => ({
    value: stage.id,
    label: stage.name,
  }))
);

const currentStage = computed(() =>
  currentPipeline.value?.stages.find(stage => stage.id === form.value.stage_id)
);

const canManageUnit = computed(
  () =>
    props.access.administrator ||
    props.access.units.some(
      unit => unit.id === form.value.business_unit_id && unit.role === 'manager'
    )
);

const ownerOptions = computed(() =>
  props.agents.map(agent => ({ value: agent.id, label: agent.name }))
);

const statusOptions = computed(() =>
  ['open', 'won', 'lost'].map(status => ({
    value: status,
    label: t(`OUTSIDER_CRM.STATUS.${status.toUpperCase()}`),
  }))
);

const lostReasonOptions = computed(() =>
  lostReasons.value
    .filter(reason => reason.active && reason.kind !== 'forward')
    .map(reason => ({ value: reason.id, label: reason.name }))
);

const readOnly = computed(() => editing.value && !editing.value.can_edit);

const isValid = computed(
  () =>
    form.value.title.trim() &&
    form.value.contact_id &&
    form.value.business_unit_id &&
    form.value.pipeline_id &&
    form.value.stage_id &&
    !Number.isNaN(parseMoney(form.value.value))
);

// ao trocar de unidade ou pipeline, volta para o primeiro pipeline e a primeira etapa aberta
watch(
  () => form.value.business_unit_id,
  () => {
    if (editing.value) return;
    if (!unitPipelines.value.some(p => p.id === form.value.pipeline_id)) {
      form.value.pipeline_id = unitPipelines.value[0]?.id ?? '';
    }
  }
);

watch(
  () => form.value.pipeline_id,
  () => {
    if (editing.value) return;
    const stages = currentPipeline.value?.stages || [];
    form.value.stage_id =
      (stages.find(stage => stage.kind === 'open') || stages[0])?.id ?? '';
  }
);

const searchContacts = async query => {
  if (!query?.trim()) return;
  try {
    const { data } = await ContactAPI.search(query.trim());
    contactOptions.value = data.payload.map(contact => ({
      value: contact.id,
      label: [contact.name, contact.phone_number].filter(Boolean).join(' · '),
    }));
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const loadSupportData = async () => {
  const [fieldsResponse, reasonsResponse] = await Promise.all([
    CrmAPI.getCustomFields(),
    CrmAPI.getLostReasons(),
  ]);
  customFields.value = fieldsResponse.data.filter(field => field.active);
  lostReasons.value = reasonsResponse.data;
  customFields.value
    .filter(field => field.field_type === 'checkbox')
    .forEach(field => {
      form.value.custom_fields[field.key] ??= false;
    });
};

const open = async (opportunity = null, defaults = {}) => {
  editing.value = opportunity;
  if (opportunity) {
    form.value = {
      ...emptyForm(),
      ...opportunity,
      value: centsToInput(opportunity.value_cents),
      expected_close_on: opportunity.expected_close_on || '',
      probability: opportunity.probability ?? '',
      owner_id: opportunity.owner?.id ?? '',
      lost_reason_id: opportunity.lost_reason_id ?? '',
      contact_id: opportunity.contact.id,
      custom_fields: { ...opportunity.custom_fields },
    };
    contactOptions.value = [
      { value: opportunity.contact.id, label: opportunity.contact.name },
    ];
  } else {
    form.value = { ...emptyForm(), ...defaults };
    form.value.pipeline_id = unitPipelines.value[0]?.id ?? '';
  }
  dialogRef.value?.open();
  try {
    await loadSupportData();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const payload = () => {
  const data = {
    title: form.value.title.trim(),
    value: parseMoney(form.value.value),
    expected_close_on: form.value.expected_close_on || null,
    probability:
      form.value.probability === '' ? null : Number(form.value.probability),
    stage_id: form.value.stage_id,
    owner_id: form.value.owner_id || null,
    custom_fields: Object.fromEntries(
      Object.entries(form.value.custom_fields).filter(
        ([, value]) => value !== '' && value !== null && value !== undefined
      )
    ),
  };
  if (editing.value) {
    return {
      ...data,
      status: form.value.status,
      lost_reason_id: form.value.lost_reason_id || null,
    };
  }
  return {
    ...data,
    contact_id: form.value.contact_id,
    business_unit_id: form.value.business_unit_id,
    pipeline_id: form.value.pipeline_id,
  };
};

const save = async () => {
  if (!isValid.value || readOnly.value) return;
  isSaving.value = true;
  try {
    const { data } = editing.value
      ? await CrmAPI.updateOpportunity(editing.value.id, payload())
      : await CrmAPI.createOpportunity(payload());
    useAlert(
      editing.value
        ? t('OUTSIDER_CRM.OPPORTUNITY.UPDATED')
        : t('OUTSIDER_CRM.OPPORTUNITY.CREATED', { code: data.code })
    );
    emit('saved', data);
    dialogRef.value?.close();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      editing
        ? `${editing.code} · ${editing.title}`
        : t('OUTSIDER_CRM.OPPORTUNITY.NEW')
    "
    width="2xl"
    overflow-y-auto
    :confirm-button-label="t('OUTSIDER_CRM.SAVE')"
    :show-confirm-button="!readOnly"
    :is-loading="isSaving"
    :disable-confirm-button="!isValid"
    @confirm="save"
  >
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <div class="flex flex-col gap-1 sm:col-span-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.OPPORTUNITY.CONTACT') }}
        </span>
        <ComboBox
          v-model="form.contact_id"
          :options="contactOptions"
          use-api-results
          :disabled="!!editing"
          :placeholder="t('OUTSIDER_CRM.OPPORTUNITY.CONTACT_PLACEHOLDER')"
          :search-placeholder="t('OUTSIDER_CRM.OPPORTUNITY.CONTACT_SEARCH')"
          :empty-state="t('OUTSIDER_CRM.OPPORTUNITY.CONTACT_EMPTY')"
          @search="searchContacts"
        />
      </div>

      <Input
        v-model="form.title"
        class="sm:col-span-2"
        :label="t('OUTSIDER_CRM.OPPORTUNITY.TITLE')"
        :placeholder="t('OUTSIDER_CRM.OPPORTUNITY.TITLE_PLACEHOLDER')"
        :disabled="readOnly"
      />

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.OPPORTUNITY.UNIT') }}
        </span>
        <Select
          v-model="form.business_unit_id"
          :options="unitOptions"
          :disabled="!!editing"
          class="!w-full [&>select]:w-full"
        />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.OPPORTUNITY.PIPELINE') }}
        </span>
        <Select
          v-model="form.pipeline_id"
          :options="pipelineOptions"
          :disabled="!!editing"
          :placeholder="t('OUTSIDER_CRM.OPPORTUNITY.NO_PIPELINE')"
          class="!w-full [&>select]:w-full"
        />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.OPPORTUNITY.STAGE') }}
        </span>
        <Select
          v-model="form.stage_id"
          :options="stageOptions"
          :disabled="readOnly"
          class="!w-full [&>select]:w-full"
        />
      </label>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.OPPORTUNITY.OWNER') }}
        </span>
        <Select
          v-model="form.owner_id"
          :options="ownerOptions"
          :disabled="readOnly || !canManageUnit"
          class="!w-full [&>select]:w-full"
        />
      </label>

      <Input
        v-model="form.value"
        :label="t('OUTSIDER_CRM.OPPORTUNITY.VALUE')"
        placeholder="0,00"
        :disabled="readOnly"
        :message-type="Number.isNaN(parseMoney(form.value)) ? 'error' : 'info'"
        :message="
          Number.isNaN(parseMoney(form.value))
            ? t('OUTSIDER_CRM.OPPORTUNITY.VALUE_INVALID')
            : ''
        "
      />

      <Input
        v-model="form.expected_close_on"
        type="date"
        :label="t('OUTSIDER_CRM.OPPORTUNITY.CLOSE_DATE')"
        :disabled="readOnly"
      />

      <Input
        v-model="form.probability"
        type="number"
        min="0"
        max="100"
        :label="t('OUTSIDER_CRM.OPPORTUNITY.PROBABILITY')"
        :placeholder="
          currentStage
            ? t('OUTSIDER_CRM.OPPORTUNITY.PROBABILITY_FROM_STAGE', {
                value: currentStage.probability,
              })
            : ''
        "
        :disabled="readOnly"
      />

      <template v-if="editing">
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.OPPORTUNITY.STATUS') }}
          </span>
          <Select
            v-model="form.status"
            :options="statusOptions"
            :disabled="readOnly || editing.status === 'forwarded'"
            class="!w-full [&>select]:w-full"
          />
        </label>
        <label v-if="form.status === 'lost'" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.OPPORTUNITY.LOST_REASON') }}
          </span>
          <Select
            v-model="form.lost_reason_id"
            :options="lostReasonOptions"
            :disabled="readOnly"
            placeholder="—"
            class="!w-full [&>select]:w-full"
          />
        </label>
      </template>

      <CustomFieldInput
        v-for="field in customFields"
        :key="field.key"
        v-model="form.custom_fields[field.key]"
        :field="field"
        :disabled="readOnly"
      />
    </div>
  </Dialog>
</template>
