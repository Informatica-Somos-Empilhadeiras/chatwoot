<script setup>
// OUTSIDER: dados da empresa que saem na proposta (confirmação de pedido, dados bancários, e-mail da
// documentação e cidade da linha de data). Padrão da conta e, se quiser, diferentes por unidade: na
// unidade só os campos preenchidos trocam o padrão.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { COMPANY_KEYS, dateLine, settingsError } from './proposalSettings';

const props = defineProps({
  settings: { type: Object, required: true },
  units: { type: Array, required: true },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();

const MULTILINE = ['address', 'bank_details'];
const unitId = ref('');
const form = ref({});
const isSaving = ref(false);

const defaults = computed(() => props.settings.company || {});
const overrides = computed(() => props.settings.unit_companies || {});
const hasOverride = id =>
  Object.values(overrides.value[String(id)] || {}).some(value => value);

const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.DEFAULT') },
  ...props.units.map(unit => ({
    value: String(unit.id),
    label: hasOverride(unit.id)
      ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.UNIT_CUSTOM', {
          name: unit.name,
        })
      : unit.name,
  })),
]);

// valores gravados para o que está selecionado (na unidade, só os que ela troca)
const stored = computed(() => {
  const source = unitId.value
    ? overrides.value[unitId.value] || {}
    : defaults.value;
  return Object.fromEntries(COMPANY_KEYS.map(key => [key, source[key] || '']));
});

const reset = () => {
  form.value = { ...stored.value };
};

watch(stored, reset, { immediate: true });

const isDirty = computed(() =>
  COMPANY_KEYS.some(key => (form.value[key] || '') !== stored.value[key])
);

const placeholder = key => (unitId.value ? defaults.value[key] || '' : '');
const preview = computed(() =>
  dateLine(form.value.city || (unitId.value ? defaults.value.city : ''))
);

const save = async values => {
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateProposalCompany(
      values,
      unitId.value || null
    );
    emit('updated', data);
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.SAVED'));
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};

// unidade volta a usar só os dados padrão
const clearUnit = () =>
  save(Object.fromEntries(COMPANY_KEYS.map(key => [key, ''])));
</script>

<template>
  <section class="flex flex-col gap-4">
    <div
      class="flex items-start gap-2 p-3 text-xs rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      <Icon icon="i-lucide-info" class="size-4 shrink-0 text-n-slate-10" />
      <span>{{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.DESCRIPTION') }}</span>
    </div>

    <div class="flex flex-wrap items-center gap-3">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.FOR') }}
      </span>
      <Select v-model="unitId" :options="unitOptions" />
      <Button
        v-if="unitId && hasOverride(unitId)"
        size="xs"
        variant="ghost"
        color="slate"
        icon="i-lucide-undo-2"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.CLEAR_UNIT')"
        :disabled="isSaving"
        @click="clearUnit"
      />
    </div>
    <p v-if="unitId" class="mb-0 -mt-2 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.UNIT_HELP') }}
    </p>

    <form
      class="grid gap-4 p-4 sm:grid-cols-2 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
      @submit.prevent="save(form)"
    >
      <template v-for="key in COMPANY_KEYS" :key="key">
        <label
          v-if="MULTILINE.includes(key)"
          class="flex flex-col gap-1 text-sm sm:col-span-2"
        >
          <span class="font-medium text-n-slate-12">
            {{
              t(
                `OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.FIELDS.${key.toUpperCase()}`
              )
            }}
          </span>
          <textarea
            v-model="form[key]"
            rows="3"
            maxlength="2000"
            class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand placeholder:text-n-slate-10"
            :placeholder="placeholder(key)"
          />
          <span class="text-xs text-n-slate-11">
            {{
              t(
                `OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.HELP.${key.toUpperCase()}`
              )
            }}
          </span>
        </label>
        <div v-else class="flex flex-col gap-1">
          <Input
            v-model="form[key]"
            maxlength="2000"
            :type="key === 'documents_email' ? 'email' : 'text'"
            :label="
              t(
                `OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.FIELDS.${key.toUpperCase()}`
              )
            "
            :placeholder="placeholder(key)"
          />
          <span class="text-xs text-n-slate-11">
            {{
              key === 'city'
                ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.HELP.CITY', {
                    example: preview,
                  })
                : t(
                    `OUTSIDER_CRM.PROPOSAL_SETTINGS.COMPANY.HELP.${key.toUpperCase()}`
                  )
            }}
          </span>
        </div>
      </template>
      <div class="flex items-center gap-2 sm:col-span-2">
        <Button
          type="submit"
          size="sm"
          :label="t('OUTSIDER_CRM.SAVE')"
          :is-loading="isSaving"
          :disabled="!isDirty"
        />
        <Button
          v-if="isDirty"
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('OUTSIDER_CRM.CANCEL')"
          @click="reset"
        />
      </div>
    </form>
  </section>
</template>
