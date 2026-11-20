<script setup>
// OUTSIDER: pagina da secao ERP. A aba vem da rota (erp/:tab): Orcamentos, OS (quadro), Pedidos e, para o administrador,
// Configuracoes. Cada aba so aparece/abre conforme o que esta ligado nas Configuracoes e o perfil de acesso.
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpBoard from '../components/ErpBoard.vue';
import ErpSettings from '../components/ErpSettings.vue';
import ErpRecordsList from '../components/ErpRecordsList.vue';
import { erpState } from '../erpStore';

const { t } = useI18n();
const route = useRoute();

const available = computed(() => {
  const tabs = [];
  if (erpState.enabled && erpState.quotesEnabled) tabs.push('orcamentos');
  if (erpState.enabled && erpState.ordersEnabled) tabs.push('os');
  if (erpState.enabled) tabs.push('pedidos');
  if (erpState.administrator) tabs.push('settings');
  return tabs;
});

const tab = computed(() =>
  available.value.includes(route.params.tab)
    ? route.params.tab
    : available.value[0] || ''
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
            {{ tab ? t(`OUTSIDER_ERP.TABS.${tab.toUpperCase()}`) : t('OUTSIDER_ERP.SIDEBAR') }}
          </span>
        </div>
      </header>
      <main class="flex-1 px-6 overflow-y-auto">
        <div class="w-full pb-8 mx-auto max-w-[110rem]">
          <ErpRecordsList v-if="tab === 'orcamentos'" key="orcamentos" kind="quotes" />
          <ErpBoard v-else-if="tab === 'os'" />
          <ErpRecordsList v-else-if="tab === 'pedidos'" key="pedidos" kind="sales" />
          <ErpSettings v-else-if="tab === 'settings'" />
          <div
            v-else
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
          >
            <Icon icon="i-lucide-clipboard-list" class="size-10 text-n-slate-9" />
            <p class="max-w-md mb-0 text-sm text-n-slate-11">
              {{
                erpState.administrator
                  ? t('OUTSIDER_ERP.STATES.OFF_ADMIN')
                  : t('OUTSIDER_ERP.STATES.OFF')
              }}
            </p>
          </div>
        </div>
      </main>
    </div>
  </section>
</template>
