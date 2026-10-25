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

const SECTIONS = [
  { key: 'central', icon: 'i-lucide-phone' },
  { key: 'goals', icon: 'i-lucide-target' },
];

const active = ref(route.query.secao === 'goals' ? 'goals' : 'central');
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
      <VoiceSettings v-if="active === 'central'" />
      <CallGoalsSettings v-else />
    </div>
  </div>
</template>
