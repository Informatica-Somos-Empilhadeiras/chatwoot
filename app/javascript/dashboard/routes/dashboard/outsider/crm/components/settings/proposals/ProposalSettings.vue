<script setup>
// OUTSIDER: Configurações > Propostas, só para administradores: numeração, dados da empresa que saem
// na proposta, modelos (textos, condições e papel timbrado) e o que cada pessoa vê e assina. Tudo fica
// nas configurações da conta, não no código (ver app/services/outsider/crm/proposal_config.rb).
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SettingsSection from '../SettingsSection.vue';
import NumberingSettings from './NumberingSettings.vue';
import CompanySettings from './CompanySettings.vue';
import TemplateSettings from './TemplateSettings.vue';
import PeopleSettings from './PeopleSettings.vue';
import { settingsError } from './proposalSettings';

defineProps({
  units: { type: Array, required: true },
});

const { t } = useI18n();

const settings = ref(null);
const isLoading = ref(true);
const failed = ref(false);
const active = ref('numbering');

const tabs = computed(() =>
  [
    { key: 'numbering', icon: 'i-lucide-hash' },
    { key: 'company', icon: 'i-lucide-building' },
    { key: 'templates', icon: 'i-lucide-file-text' },
    { key: 'people', icon: 'i-lucide-users' },
  ].map(tab => ({
    ...tab,
    label: t(`OUTSIDER_CRM.PROPOSAL_SETTINGS.TABS.${tab.key.toUpperCase()}`),
  }))
);

const load = async () => {
  isLoading.value = true;
  failed.value = false;
  try {
    const { data } = await CrmAPI.getProposalSettings();
    settings.value = data;
  } catch (error) {
    failed.value = true;
    useAlert(settingsError(t, error));
  } finally {
    isLoading.value = false;
  }
};

// toda alteração devolve as configurações inteiras
const refresh = data => {
  settings.value = data;
};

onMounted(load);
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TITLE')"
    :description="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.DESCRIPTION')"
  >
    <nav class="flex gap-1 overflow-x-auto border-b border-n-weak">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="flex items-center gap-2 px-3 py-2 -mb-px text-sm border-b-2 whitespace-nowrap"
        :class="
          active === tab.key
            ? 'border-n-brand text-n-slate-12 font-medium'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="active = tab.key"
      >
        <span :class="tab.icon" class="size-4" />
        {{ tab.label }}
      </button>
    </nav>

    <TemplateSettings v-if="active === 'templates'" />
    <div v-else-if="isLoading" class="flex justify-center p-8">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else-if="failed || !settings"
      class="flex flex-col items-center gap-3 p-8 text-sm text-n-slate-11"
    >
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LOAD_FAILED') }}
      <Button
        size="sm"
        variant="faded"
        icon="i-lucide-refresh-cw"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.RETRY')"
        @click="load"
      />
    </div>
    <NumberingSettings
      v-else-if="active === 'numbering'"
      :settings="settings"
      @updated="refresh"
    />
    <CompanySettings
      v-else-if="active === 'company'"
      :settings="settings"
      :units="units"
      @updated="refresh"
    />
    <PeopleSettings v-else :settings="settings" @updated="refresh" />
  </SettingsSection>
</template>
