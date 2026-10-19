<script setup>
// OUTSIDER: motivos de perda e de encaminhamento. Quando existe algum motivo de perda,
// marcar uma oportunidade como perdida passa a exigir o motivo.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage } from '../../helpers';

const { t } = useI18n();

const reasons = ref([]);
const newName = ref('');
const newKind = ref('lost');

const kindOptions = computed(() =>
  ['lost', 'forward', 'both'].map(kind => ({
    value: kind,
    label: t(`OUTSIDER_CRM.SETTINGS.REASONS.KINDS.${kind.toUpperCase()}`),
  }))
);

const load = async () => {
  try {
    const { data } = await CrmAPI.getLostReasons();
    reasons.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const add = async () => {
  if (!newName.value.trim()) return;
  try {
    await CrmAPI.createLostReason({
      name: newName.value.trim(),
      kind: newKind.value,
      position: reasons.value.length + 1,
    });
    newName.value = '';
    await load();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const update = async (reason, attributes) => {
  try {
    await CrmAPI.updateLostReason(reason.id, attributes);
    await load();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const remove = async reason => {
  try {
    await CrmAPI.deleteLostReason(reason.id);
    await load();
  } catch (error) {
    useAlert(
      error?.response?.data?.error === 'in_use'
        ? t('OUTSIDER_CRM.SETTINGS.REASONS.IN_USE')
        : errorMessage(t, error)
    );
  }
};

onMounted(load);
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.REASONS.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.REASONS.DESCRIPTION')"
  >
    <form class="flex flex-wrap items-center gap-2" @submit.prevent="add">
      <Input
        v-model="newName"
        class="flex-1 min-w-[12rem]"
        :placeholder="t('OUTSIDER_CRM.SETTINGS.REASONS.PLACEHOLDER')"
      />
      <Select v-model="newKind" :options="kindOptions" />
      <Button
        type="submit"
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.SETTINGS.REASONS.ADD')"
        :disabled="!newName.trim()"
      />
    </form>
    <div
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <p
        v-if="!reasons.length"
        class="p-6 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.SETTINGS.REASONS.EMPTY') }}
      </p>
      <div
        v-for="reason in reasons"
        :key="reason.id"
        class="flex flex-wrap items-center justify-between gap-2 px-4 py-2 border-b border-n-weak last:border-0"
      >
        <span
          class="text-sm"
          :class="reason.active ? 'text-n-slate-12' : 'text-n-slate-10'"
        >
          {{ reason.name }}
        </span>
        <div class="flex items-center gap-2">
          <Select
            :model-value="reason.kind"
            :options="kindOptions"
            @update:model-value="kind => update(reason, { kind })"
          />
          <Switch
            v-tooltip.top="t('OUTSIDER_CRM.SETTINGS.ACTIVE')"
            :model-value="reason.active"
            @change="update(reason, { active: !reason.active })"
          />
          <Button
            icon="i-lucide-trash-2"
            size="sm"
            variant="ghost"
            color="ruby"
            @click="remove(reason)"
          />
        </div>
      </div>
    </div>
  </SettingsSection>
</template>
