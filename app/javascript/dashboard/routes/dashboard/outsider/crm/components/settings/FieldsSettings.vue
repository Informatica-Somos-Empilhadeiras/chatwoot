<script setup>
// OUTSIDER: campos personalizados das oportunidades (ex.: CNPJ, segmento, tamanho da frota).
// A chave é gerada do nome e não muda depois, porque os valores gravados usam essa chave.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage, normalize } from '../../helpers';

const { t } = useI18n();

const fields = ref([]);
const dialogRef = ref(null);
const isSaving = ref(false);
const form = ref({});

const TYPES = ['text', 'number', 'currency', 'date', 'list', 'checkbox'];

const typeOptions = computed(() =>
  TYPES.map(type => ({
    value: type,
    label: t(`OUTSIDER_CRM.SETTINGS.FIELDS.TYPES.${type.toUpperCase()}`),
  }))
);

const typeLabel = type =>
  t(`OUTSIDER_CRM.SETTINGS.FIELDS.TYPES.${type.toUpperCase()}`);

const keyFromLabel = label =>
  normalize(label)
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .replace(/^(\d)/, 'campo_$1');

const options = computed(() =>
  (form.value.optionsText || '')
    .split('\n')
    .map(option => option.trim())
    .filter(Boolean)
);

const isValid = computed(
  () =>
    form.value.label?.trim() &&
    (form.value.id || keyFromLabel(form.value.label)) &&
    (form.value.field_type !== 'list' || options.value.length)
);

const load = async () => {
  try {
    const { data } = await CrmAPI.getCustomFields();
    fields.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const openDialog = (field = null) => {
  form.value = field
    ? { ...field, optionsText: (field.options || []).join('\n') }
    : { label: '', field_type: 'text', required: false, optionsText: '' };
  dialogRef.value?.open();
};

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  const attributes = {
    label: form.value.label.trim(),
    field_type: form.value.field_type,
    required: form.value.required,
    options: options.value,
  };
  try {
    if (form.value.id) {
      await CrmAPI.updateCustomField(form.value.id, attributes);
    } else {
      await CrmAPI.createCustomField({
        ...attributes,
        key: keyFromLabel(form.value.label),
        position: fields.value.length + 1,
      });
    }
    dialogRef.value?.close();
    await load();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

const toggleActive = async field => {
  try {
    await CrmAPI.updateCustomField(field.id, { active: !field.active });
    await load();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

onMounted(load);
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.FIELDS.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.FIELDS.DESCRIPTION')"
  >
    <template #actions>
      <Button
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.SETTINGS.FIELDS.NEW')"
        @click="openDialog()"
      />
    </template>
    <div
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <p
        v-if="!fields.length"
        class="p-6 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.SETTINGS.FIELDS.EMPTY') }}
      </p>
      <div
        v-for="field in fields"
        :key="field.id"
        class="flex flex-wrap items-center justify-between gap-2 px-4 py-2 border-b border-n-weak last:border-0"
      >
        <div class="flex flex-col min-w-0">
          <span
            class="text-sm"
            :class="field.active ? 'text-n-slate-12' : 'text-n-slate-10'"
          >
            {{ field.label }}
            <span v-if="field.required" class="text-n-ruby-9">*</span>
          </span>
          <span class="text-xs text-n-slate-11">
            {{ typeLabel(field.field_type) }} · {{ field.key }}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <Switch
            v-tooltip.top="t('OUTSIDER_CRM.SETTINGS.ACTIVE')"
            :model-value="field.active"
            @change="toggleActive(field)"
          />
          <Button
            icon="i-lucide-pencil"
            size="sm"
            variant="ghost"
            color="slate"
            @click="openDialog(field)"
          />
        </div>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      :title="
        form.id
          ? t('OUTSIDER_CRM.SETTINGS.FIELDS.EDIT')
          : t('OUTSIDER_CRM.SETTINGS.FIELDS.NEW')
      "
      :confirm-button-label="t('OUTSIDER_CRM.SAVE')"
      :is-loading="isSaving"
      :disable-confirm-button="!isValid"
      @confirm="save"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.label"
          :label="t('OUTSIDER_CRM.SETTINGS.FIELDS.LABEL')"
          :placeholder="t('OUTSIDER_CRM.SETTINGS.FIELDS.LABEL_PLACEHOLDER')"
        />
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.FIELDS.TYPE') }}
          </span>
          <Select
            v-model="form.field_type"
            :options="typeOptions"
            class="!w-full [&>select]:w-full"
          />
        </label>
        <label
          v-if="form.field_type === 'list'"
          class="flex flex-col gap-1 text-sm"
        >
          <span class="font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.FIELDS.OPTIONS') }}
          </span>
          <textarea
            v-model="form.optionsText"
            rows="4"
            class="!mb-0 rounded-lg"
            :placeholder="t('OUTSIDER_CRM.SETTINGS.FIELDS.OPTIONS_PLACEHOLDER')"
          />
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch v-model="form.required" />
          {{ t('OUTSIDER_CRM.SETTINGS.FIELDS.REQUIRED') }}
        </label>
      </div>
    </Dialog>
  </SettingsSection>
</template>
