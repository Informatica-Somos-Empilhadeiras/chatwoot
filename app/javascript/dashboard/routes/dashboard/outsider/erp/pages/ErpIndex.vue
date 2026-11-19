<script setup>
// OUTSIDER: página Ordens de serviço: o quadro das OS do ERP Mais Prático e, para administradores, as Configurações da
// integração. A seção vem da rota (ordens-servico/:tab), escolhida pelos subitens do menu lateral.
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpBoard from '../components/ErpBoard.vue';
import ErpSettings from '../components/ErpSettings.vue';
import { erpState } from '../erpStore';

const { t } = useI18n();
const route = useRoute();

const tab = computed(() =>
  route.params.tab === 'settings' && erpState.administrator
    ? 'settings'
    : 'board'
);
</script>

<template>
  <section class="flex w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex flex-col w-full h-full">
      <header class="px-6">
        <div class="flex flex-col gap-0.5 pt-6 pb-4 mx-auto max-w-[110rem]">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('OUTSIDER_ERP.TITLE') }}
          </span>
          <span class="text-xl font-medium text-n-slate-12">
            {{ t(`OUTSIDER_ERP.TABS.${tab.toUpperCase()}`) }}
          </span>
        </div>
      </header>
      <main class="flex-1 px-6 overflow-y-auto">
        <div class="w-full pb-8 mx-auto max-w-[110rem]">
          <ErpSettings v-if="tab === 'settings'" />
          <div
            v-else-if="erpState.loaded && !erpState.enabled"
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
          >
            <Icon
              icon="i-lucide-clipboard-list"
              class="size-10 text-n-slate-9"
            />
            <p class="max-w-md mb-0 text-sm text-n-slate-11">
              {{
                erpState.administrator
                  ? t('OUTSIDER_ERP.STATES.OFF_ADMIN')
                  : t('OUTSIDER_ERP.STATES.OFF')
              }}
            </p>
            <router-link
              v-if="erpState.administrator"
              :to="{ name: 'outsider_erp', params: { tab: 'settings' } }"
              class="text-sm text-n-blue-11 hover:underline"
            >
              {{ t('OUTSIDER_ERP.TABS.SETTINGS') }}
            </router-link>
          </div>
          <ErpBoard v-else-if="erpState.enabled" />
        </div>
      </main>
    </div>
  </section>
</template>
