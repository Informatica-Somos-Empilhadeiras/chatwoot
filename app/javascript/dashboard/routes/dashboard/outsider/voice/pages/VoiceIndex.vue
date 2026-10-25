<script setup>
// OUTSIDER: Telefonia (Entrega 23), fora do CRM: Painel (wallboard), Ligações (fila de retorno e histórico)
// e Configurações (operadora, números, ramais e metas). A seção vem da rota (telefonia/:tab), escolhida
// pelos subitens do menu lateral. Usa o acesso do CRM (ver ../sections.js).
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Wallboard from '../components/Wallboard.vue';
import CallsPanel from '../components/CallsPanel.vue';
import VoiceSettingsPage from '../components/settings/VoiceSettingsPage.vue';
import { crmState, ensureCrmContext } from '../../crm/crmStore';
import { voiceSections } from '../sections';

const { t } = useI18n();
const route = useRoute();

const isLoading = ref(true);
const access = computed(() => crmState.access);
const sections = computed(() => voiceSections(access.value));

const activeTab = computed(
  () =>
    sections.value.find(section => section.key === route.params.tab)?.key ||
    sections.value[0]?.key
);
const activeSection = computed(() =>
  sections.value.find(section => section.key === activeTab.value)
);

onMounted(async () => {
  await ensureCrmContext();
  isLoading.value = false;
});

// conta trocada no menu: o acesso é buscado de novo pelo crmStore
watch(
  () => route.params.accountId,
  () => ensureCrmContext()
);
</script>

<template>
  <section class="flex w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex flex-col w-full h-full">
      <header class="px-6">
        <div
          class="flex flex-col w-full gap-0.5 pt-6 pb-4 mx-auto max-w-[90rem]"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('OUTSIDER_VOICE.SECTION.TITLE') }}
          </span>
          <span class="text-xl font-medium truncate text-n-slate-12">
            {{ activeSection ? t(activeSection.label) : '' }}
          </span>
        </div>
      </header>
      <main class="flex-1 px-6 overflow-y-auto">
        <div class="w-full pb-8 mx-auto max-w-[90rem]">
          <div v-if="isLoading" class="flex justify-center p-8">
            <Spinner class="text-n-slate-10" />
          </div>
          <div
            v-else-if="!sections.length"
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
          >
            <Icon icon="i-lucide-phone-off" class="size-10 text-n-slate-9" />
            <p class="max-w-md mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_VOICE.SECTION.NO_ACCESS') }}
            </p>
          </div>
          <Wallboard v-else-if="activeTab === 'dashboard'" :access="access" />
          <CallsPanel v-else-if="activeTab === 'calls'" :access="access" />
          <VoiceSettingsPage v-else />
        </div>
      </main>
    </div>
  </section>
</template>
