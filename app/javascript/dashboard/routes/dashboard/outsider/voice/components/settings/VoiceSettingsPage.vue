<script setup>
// OUTSIDER: Telefonia > Configurações (Entrega 23): a central (operadora, números, ramais) e as metas de
// ligação, cada uma na sua seção, como nas Configurações do CRM. Só administradores.
import { ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import VoiceSettings from './VoiceSettings.vue';
import CallGoalsSettings from './CallGoalsSettings.vue';

const { t } = useI18n();
const route = useRoute();

// Entrega 25: gravações, custos e filiais (a mesma tela da central, outra parte)
const SECTIONS = [
  { key: 'central', icon: 'i-lucide-phone' },
  { key: 'recording', icon: 'i-lucide-disc-3' },
  { key: 'costs', icon: 'i-lucide-receipt' },
  { key: 'branches', icon: 'i-lucide-building-2' },
  { key: 'goals', icon: 'i-lucide-target' },
];

const active = ref(
  SECTIONS.some(section => section.key === route.query.secao)
    ? route.query.secao
    : 'central'
);
</script>

<template>
  <div class="flex flex-col gap-6 md:flex-row">
    <nav class="flex gap-1 overflow-x-auto md:flex-col md:w-48 shrink-0">
      <button
        v-for="section in SECTIONS"
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
        {{ t(`OUTSIDER_VOICE.SECTION.SETTINGS.${section.key.toUpperCase()}`) }}
      </button>
    </nav>
    <div class="flex-1 min-w-0">
      <CallGoalsSettings v-if="active === 'goals'" />
      <VoiceSettings v-else :key="active" :part="active" />
    </div>
  </div>
</template>
