<script setup>
// OUTSIDER: modelo novo, em branco (textos e condições padrão do tipo, papel timbrado do CRM) ou copiando
// outro modelo da conta. A cópia usa as mesmas imagens do original, sem duplicar arquivo.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { settingsError } from './proposalSettings';

const props = defineProps({
  templates: { type: Array, required: true },
});

const emit = defineEmits(['created']);

const { t } = useI18n();

const dialogRef = ref(null);
const name = ref('');
const kind = ref('sale');
const sourceId = ref('');
const isSaving = ref(false);

const source = computed(() =>
  props.templates.find(template => template.id === Number(sourceId.value))
);

const kindOptions = computed(() =>
  ['sale', 'rental'].map(value => ({
    value,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.KINDS.${value.toUpperCase()}`
    ),
  }))
);

const sourceOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.BLANK') },
  ...props.templates.map(template => ({
    value: template.id,
    label: template.name,
  })),
]);

// copiar define o tipo: o modelo de locação continua de locação
const onSource = value => {
  sourceId.value = value;
  if (source.value) kind.value = source.value.kind;
};

const open = (copyOf = null) => {
  sourceId.value = copyOf?.id ?? '';
  kind.value = copyOf?.kind ?? 'sale';
  name.value = copyOf
    ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.COPY_NAME', {
        name: copyOf.name,
      })
    : '';
  dialogRef.value?.open();
};

const create = async () => {
  if (!name.value.trim()) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.createProposalTemplate({
      name: name.value.trim(),
      kind: kind.value,
      source_id: source.value?.id,
    });
    emit('created', data);
    dialogRef.value?.close();
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.CREATED'));
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.TITLE')"
    :description="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.DESCRIPTION')"
    :confirm-button-label="
      t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.CREATE')
    "
    :is-loading="isSaving"
    :disable-confirm-button="!name.trim()"
    @confirm="create"
  >
    <div class="flex flex-col gap-4" data-new-template>
      <Input
        v-model="name"
        maxlength="255"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.NAME')"
      />
      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.SOURCE') }}
        </span>
        <Select
          :model-value="sourceId"
          :options="sourceOptions"
          @update:model-value="onSource"
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.KIND') }}
        </span>
        <Select v-model="kind" :options="kindOptions" :disabled="!!source" />
        <span class="text-xs text-n-slate-11">
          {{
            source
              ? t(
                  'OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.KIND_FROM_SOURCE'
                )
              : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.KIND_HELP')
          }}
        </span>
      </label>
    </div>
  </Dialog>
</template>
