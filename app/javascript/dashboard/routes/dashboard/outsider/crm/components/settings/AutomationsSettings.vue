<script setup>
// OUTSIDER: automações do CRM (ver app/services/outsider/crm/automations.rb e
// stalled_opportunities.rb). Todas começam desligadas; cada ação fica na linha do tempo do negócio.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage } from '../../helpers';
import { refreshMyTasks } from '../../crmStore';

const props = defineProps({
  access: { type: Object, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const store = useStore();
const labels = useMapGetter('labels/getLabels');

const current = props.access.settings || {};
const form = ref({
  automation_won_label: current.automation_won_label || '',
  automation_lost_label: current.automation_lost_label || '',
  automation_close_tasks: Boolean(current.automation_close_tasks),
  automation_stalled_task: Boolean(current.automation_stalled_task),
  automation_stalled_days: current.automation_stalled_days ?? 7,
});
const isSaving = ref(false);
const isChecking = ref(false);

const labelOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.NO_LABEL') },
  ...labels.value.map(label => ({ value: label.title, label: label.title })),
]);

const save = async () => {
  isSaving.value = true;
  try {
    await CrmAPI.updateSettings({
      ...form.value,
      automation_stalled_days: Number(form.value.automation_stalled_days),
    });
    useAlert(t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.SAVED'));
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

const checkNow = async () => {
  isChecking.value = true;
  try {
    const { data } = await CrmAPI.checkStalled();
    useAlert(
      t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.CHECKED', { count: data.created })
    );
    // as tarefas novas podem ser de quem está na tela: atualiza o contador da aba Tarefas
    if (data.created) refreshMyTasks();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isChecking.value = false;
  }
};

onMounted(() => store.dispatch('labels/get'));
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.DESCRIPTION')"
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <div
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.LABELS_TITLE') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.LABEL_HELP') }}
          </span>
        </div>
        <div class="flex flex-wrap gap-4">
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.WON_LABEL') }}
            <Select
              v-model="form.automation_won_label"
              :options="labelOptions"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.LOST_LABEL') }}
            <Select
              v-model="form.automation_lost_label"
              :options="labelOptions"
            />
          </label>
        </div>
      </div>

      <div
        class="flex items-start gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <Switch v-model="form.automation_close_tasks" class="mt-0.5" />
        <div class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.CLOSE_TASKS') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.CLOSE_TASKS_HELP') }}
          </span>
        </div>
      </div>

      <div
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="flex items-start gap-3">
          <Switch v-model="form.automation_stalled_task" class="mt-0.5" />
          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.STALLED_TASK') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.STALLED_HELP') }}
            </span>
          </div>
        </div>
        <div class="flex flex-wrap items-end gap-3 ltr:pl-10 rtl:pr-10">
          <Input
            v-model="form.automation_stalled_days"
            type="number"
            min="1"
            max="90"
            class="w-40"
            :disabled="!form.automation_stalled_task"
            :label="t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.STALLED_DAYS')"
          />
          <Button
            type="button"
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-refresh-cw"
            :label="t('OUTSIDER_CRM.SETTINGS.AUTOMATIONS.CHECK_NOW')"
            :disabled="!access.settings?.automation_stalled_task"
            :is-loading="isChecking"
            @click="checkNow"
          />
        </div>
      </div>

      <div>
        <Button
          type="submit"
          size="sm"
          :label="t('OUTSIDER_CRM.SAVE')"
          :is-loading="isSaving"
        />
      </div>
    </form>
  </SettingsSection>
</template>
