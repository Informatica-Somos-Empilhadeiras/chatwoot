<script setup>
// OUTSIDER: pagina da secao ERP. A aba vem da rota (erp/:tab): Orcamentos, OS e Pedidos (todo o historico do ERP, com
// filtros, tabela e o painel de detalhe, ErpRecords) e, para o administrador, as Configuracoes. A OS tambem tem o quadro
// (espelho). Um erro dentro de uma aba aparece na tela com a mensagem em vez de deixar a pagina em branco.
import { ref, computed, watch, onErrorCaptured } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ErpBoard from '../components/ErpBoard.vue';
import ErpSettings from '../components/ErpSettings.vue';
import ErpRecords from '../records/ErpRecords.vue';
import { kindForTab } from '../records/recordsConfig';
import { erpTabs } from '../sidebar';
import { erpState, ERP_ROUTE } from '../erpStore';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const MODE_KEY = 'outsider-erp-os-mode';
const storedMode = () => {
  try {
    return window.localStorage.getItem(MODE_KEY) === 'board' ? 'board' : 'table';
  } catch {
    return 'table';
  }
};

const tabs = computed(() => erpTabs());
const tab = computed(() => {
  const names = tabs.value.map(item => item.name);
  return names.includes(route.params.tab) ? route.params.tab : names[0] || '';
});
const kind = computed(() => kindForTab(tab.value));
const osMode = ref(storedMode());
const showBoard = computed(() => tab.value === 'os' && osMode.value === 'board');
const fills = computed(() => kind.value && !showBoard.value);

const setMode = value => {
  osMode.value = value;
  try {
    window.localStorage.setItem(MODE_KEY, value);
  } catch {
    // sem armazenamento: só não lembra
  }
};

const go = name => {
  if (name === tab.value) return;
  router.push({ name: ERP_ROUTE, params: { ...route.params, tab: name } });
};

// erro numa aba: mostra o motivo (antes a aba ficava em branco)
const crash = ref('');
onErrorCaptured(error => {
  crash.value = error?.message || String(error);
  // eslint-disable-next-line no-console
  console.error('[ERP]', error);
  return false;
});
watch(tab, () => {
  crash.value = '';
});
</script>

<template>
  <section class="flex w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex flex-col w-full h-full min-w-0">
      <header class="px-4 shrink-0 sm:px-6">
        <div
          class="flex flex-wrap items-end justify-between gap-3 pt-5 pb-4 mx-auto max-w-[110rem]"
        >
          <div class="flex flex-col gap-0.5 min-w-0">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('OUTSIDER_ERP.TITLE') }}
            </span>
            <h1 class="mb-0 text-xl font-medium text-n-slate-12">
              {{
                tab
                  ? t(`OUTSIDER_ERP.TABS.${tab.toUpperCase()}`)
                  : t('OUTSIDER_ERP.SIDEBAR')
              }}
            </h1>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <div
              v-if="tab === 'os'"
              class="flex items-center p-0.5 rounded-lg bg-n-alpha-2"
            >
              <button
                v-for="mode in ['table', 'board']"
                :key="mode"
                type="button"
                class="flex items-center gap-1.5 h-7 px-2.5 text-xs rounded-md"
                :class="
                  osMode === mode
                    ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                    : 'text-n-slate-11 hover:text-n-slate-12'
                "
                @click="setMode(mode)"
              >
                <Icon
                  :icon="mode === 'board' ? 'i-lucide-kanban' : 'i-lucide-list'"
                  class="size-3.5"
                />
                {{
                  t(
                    `OUTSIDER_ERP.RECORDS.ORDERS.${mode === 'board' ? 'BOARD' : 'TABLE'}`
                  )
                }}
              </button>
            </div>
            <nav
              v-if="tabs.length > 1"
              class="flex items-center gap-0.5 p-0.5 overflow-x-auto rounded-lg bg-n-alpha-2"
            >
              <button
                v-for="item in tabs"
                :key="item.name"
                type="button"
                class="flex items-center gap-1.5 h-8 px-3 text-[13px] rounded-md whitespace-nowrap"
                :class="
                  tab === item.name
                    ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                    : 'text-n-slate-11 hover:text-n-slate-12'
                "
                @click="go(item.name)"
              >
                <Icon :icon="item.icon" class="size-4" />
                <span class="hidden md:inline">{{ t(item.label) }}</span>
              </button>
            </nav>
          </div>
        </div>
      </header>
      <main
        class="flex-1 min-h-0 px-4 sm:px-6"
        :class="fills ? 'overflow-y-auto md:overflow-hidden' : 'overflow-y-auto'"
      >
        <div
          class="w-full mx-auto max-w-[110rem]"
          :class="fills ? 'md:h-full pb-4 md:pb-0' : 'pb-8'"
        >
          <div
            v-if="crash"
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-ruby-2"
          >
            <Icon icon="i-lucide-triangle-alert" class="size-8 text-n-ruby-11" />
            <p class="max-w-xl mb-0 text-sm break-words text-n-ruby-11">
              {{ t('OUTSIDER_ERP.RECORDS.ERROR', { message: crash }) }}
            </p>
            <Button
              size="sm"
              variant="faded"
              color="slate"
              :label="t('OUTSIDER_ERP.CONTACT.RETRY')"
              @click="crash = ''"
            />
          </div>
          <ErpBoard v-else-if="showBoard" />
          <ErpRecords v-else-if="kind" :key="kind" :kind="kind" />
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
