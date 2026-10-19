<script setup>
// OUTSIDER: opções gerais do CRM da conta (ver app/services/outsider/crm/settings.rb).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage } from '../../helpers';

const props = defineProps({
  access: { type: Object, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const maxAttempts = ref(props.access.settings?.max_forward_attempts ?? 3);
const isSaving = ref(false);

const save = async () => {
  isSaving.value = true;
  try {
    await CrmAPI.updateSettings({
      max_forward_attempts: Number(maxAttempts.value),
    });
    useAlert(t('OUTSIDER_CRM.SETTINGS.GENERAL.SAVED'));
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.GENERAL.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.GENERAL.DESCRIPTION')"
  >
    <form class="flex flex-wrap items-end gap-3" @submit.prevent="save">
      <Input
        v-model="maxAttempts"
        type="number"
        min="1"
        max="10"
        class="w-48"
        :label="t('OUTSIDER_CRM.SETTINGS.GENERAL.MAX_ATTEMPTS')"
      />
      <Button
        type="submit"
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
      />
    </form>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.SETTINGS.GENERAL.MAX_ATTEMPTS_HELP') }}
    </p>
  </SettingsSection>
</template>
