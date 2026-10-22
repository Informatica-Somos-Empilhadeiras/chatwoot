<script setup>
// OUTSIDER: próximo número de proposta. Serve para continuar a numeração que a empresa já usa
// (ex.: a última no papel foi 2660, então a próxima é 2661).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { settingsError } from './proposalSettings';

const props = defineProps({
  settings: { type: Object, required: true },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();
const nextNumber = ref(props.settings.next_number);
const isSaving = ref(false);

watch(
  () => props.settings.next_number,
  value => {
    nextNumber.value = value;
  }
);

const number = computed(() => Number(nextNumber.value));
const isValid = computed(
  () => Number.isInteger(number.value) && number.value >= 1
);
const lastNumber = computed(() => props.settings.last_number);
// número que já existe: o servidor aceita, mas a proposta nova vai repetir ou pular números
const reusesNumber = computed(
  () => isValid.value && lastNumber.value && number.value <= lastNumber.value
);
const isDirty = computed(() => number.value !== props.settings.next_number);

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateProposalGeneral({
      next_number: number.value,
    });
    emit('updated', data);
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NUMBERING.SAVED'));
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <section class="flex flex-col gap-3">
    <p class="mb-0 text-sm text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NUMBERING.DESCRIPTION') }}
    </p>
    <form class="flex flex-wrap items-end gap-3" @submit.prevent="save">
      <Input
        v-model="nextNumber"
        type="number"
        min="1"
        max="99999999"
        class="w-48"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NUMBERING.NEXT')"
        :message-type="isValid ? 'info' : 'error'"
      />
      <Button
        type="submit"
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="!isValid || !isDirty"
      />
    </form>
    <p class="mb-0 text-xs text-n-slate-11">
      {{
        lastNumber
          ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NUMBERING.LAST', {
              number: lastNumber,
            })
          : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NUMBERING.NONE')
      }}
    </p>
    <p
      v-if="reusesNumber"
      class="flex items-center gap-1.5 mb-0 text-xs text-n-amber-11"
    >
      <Icon icon="i-lucide-triangle-alert" class="size-3.5 shrink-0" />
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NUMBERING.REUSE') }}
    </p>
  </section>
</template>
