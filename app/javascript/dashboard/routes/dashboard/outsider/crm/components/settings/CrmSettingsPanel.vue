<script setup>
// OUTSIDER: configurações do CRM. Administradores veem tudo; gestores de unidade só os
// pipelines das suas unidades. ?secao=goals abre direto numa seção (botões da aba Metas).
import { ref, computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import UnitsSettings from './UnitsSettings.vue';
import PipelinesSettings from './PipelinesSettings.vue';
import ReasonsSettings from './ReasonsSettings.vue';
import FieldsSettings from './FieldsSettings.vue';
import GeneralSettings from './GeneralSettings.vue';
import AutomationsSettings from './AutomationsSettings.vue';
import GoalsSettings from './GoalsSettings.vue';
import CommissionSettings from './CommissionSettings.vue';

const props = defineProps({
  access: { type: Object, required: true },
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const route = useRoute();

const sections = computed(() =>
  [
    { key: 'units', icon: 'i-lucide-building-2', admin: true },
    { key: 'pipelines', icon: 'i-lucide-kanban', admin: false },
    { key: 'reasons', icon: 'i-lucide-circle-x', admin: true },
    { key: 'fields', icon: 'i-lucide-text-cursor-input', admin: true },
    { key: 'automations', icon: 'i-lucide-bot', admin: true },
    { key: 'goals', icon: 'i-lucide-target', admin: true },
    { key: 'commission', icon: 'i-lucide-percent', admin: true },
    { key: 'general', icon: 'i-lucide-settings-2', admin: true },
  ]
    .filter(section => props.access.administrator || !section.admin)
    .map(section => ({
      ...section,
      label: t(`OUTSIDER_CRM.SETTINGS.SECTIONS.${section.key.toUpperCase()}`),
    }))
);

const active = ref(
  sections.value.some(section => section.key === route.query.secao)
    ? route.query.secao
    : sections.value[0].key
);
</script>

<template>
  <div class="flex flex-col gap-6 md:flex-row">
    <nav class="flex gap-1 overflow-x-auto md:flex-col md:w-48 shrink-0">
      <button
        v-for="section in sections"
        :key="section.key"
        type="button"
        class="flex items-center gap-2 px-3 py-2 text-sm text-left rounded-lg whitespace-nowrap"
        :class="
          active === section.key
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="active = section.key"
      >
        <span :class="section.icon" class="size-4" />
        {{ section.label }}
      </button>
    </nav>
    <div class="flex-1 min-w-0">
      <UnitsSettings
        v-if="active === 'units'"
        :units="units"
        @changed="emit('changed')"
      />
      <PipelinesSettings
        v-else-if="active === 'pipelines'"
        :access="access"
        :units="units"
        :pipelines="pipelines"
        @changed="emit('changed')"
      />
      <ReasonsSettings v-else-if="active === 'reasons'" />
      <FieldsSettings v-else-if="active === 'fields'" />
      <AutomationsSettings
        v-else-if="active === 'automations'"
        :access="access"
        :units="units"
        :pipelines="pipelines"
        @changed="emit('changed')"
      />
      <GoalsSettings v-else-if="active === 'goals'" :units="units" />
      <CommissionSettings v-else-if="active === 'commission'" :units="units" />
      <GeneralSettings v-else :access="access" @changed="emit('changed')" />
    </div>
  </div>
</template>
