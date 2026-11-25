<script setup>
// OUTSIDER: pagina da secao ERP. A aba vem da rota (erp/:tab): Orcamentos, OS, Pedidos e Notas fiscais (todo o historico
// do ERP, com filtros, tabela e o painel de detalhe, ErpRecords) e, para o administrador, as Configuracoes. A OS tambem
// tem o quadro (espelho); as Notas trocam entre Produtos (NF-e) e Servicos (NFS-e). "Novo cliente" cadastra no ERP (com a
// gravacao de clientes ligada). Produtos: consulta do cadastro com as fotos (ErpProducts). Modelos de relatorio: o estudio
// dos relatorios da OS e do orcamento (ErpPrints, administrador). Um erro dentro de uma aba aparece na tela com a mensagem em vez de deixar a pagina em branco.
// Navegacao em dois niveis: os grupos (Orcamentos e OS, Fiscal e financeiro, Relatorios e desempenho, Configuracoes,
// sidebar.js ERP_GROUPS) em cima e as abas do grupo embaixo; Lista/Quadro (OS) e Produtos/Servicos (notas) na linha das abas.
import { ref, computed, watch, onErrorCaptured } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ErpBoard from '../components/ErpBoard.vue';
import ErpSettings from '../components/ErpSettings.vue';
import ErpProducts from '../products/ErpProducts.vue';
import ErpRecords from '../records/ErpRecords.vue';
import ErpPrints from '../prints/ErpPrints.vue';
import ErpClientDialog from '../clients/ErpClientDialog.vue';
import { kindForTab } from '../records/recordsConfig';
import { erpTabs, erpGroups } from '../sidebar';
import { reportTabs } from '../../reports/reportsCatalog';
import { erpState, ERP_ROUTE } from '../erpStore';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const MODE_KEY = 'outsider-erp-os-mode';
const NOTES_KEY = 'outsider-erp-notes-mode';
const NOTE_KINDS = ['invoices', 'service_invoices'];
const stored = (key, allowed, fallback) => {
  try {
    const value = window.localStorage.getItem(key);
    return allowed.includes(value) ? value : fallback;
  } catch {
    return fallback;
  }
};
const remember = (key, value) => {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // sem armazenamento: só não lembra
  }
};

const tabs = computed(() => erpTabs());
// relatórios: abas separadas das dos módulos (reports/reportsCatalog.js)
const reports = computed(() => (erpState.loaded ? reportTabs() : []));
const tab = computed(() => {
  const names = [...tabs.value, ...reports.value].map(item => item.name);
  return names.includes(route.params.tab) ? route.params.tab : names[0] || '';
});
const go = name => {
  if (name === tab.value) return;
  router.push({ name: ERP_ROUTE, params: { ...route.params, tab: name } });
};

const groups = computed(() => erpGroups());
const currentGroup = computed(
  () =>
    groups.value.find(group =>
      group.items.some(item => item.name === tab.value)
    ) || null
);
// a última aba aberta em cada grupo: voltar ao grupo volta nela
const lastInGroup = ref({});
watch(
  [tab, currentGroup],
  ([name, group]) => {
    if (group) lastInGroup.value = { ...lastInGroup.value, [group.key]: name };
  },
  { immediate: true }
);
const goGroup = group => {
  const last = lastInGroup.value[group.key];
  const target = group.items.some(item => item.name === last)
    ? last
    : group.items[0].name;
  go(target);
};
const notesMode = ref(stored(NOTES_KEY, NOTE_KINDS, 'invoices'));
const currentReport = computed(() =>
  reports.value.find(item => item.name === tab.value)
);
const kind = computed(() =>
  tab.value === 'notas' ? notesMode.value : kindForTab(tab.value)
);
const osMode = ref(stored(MODE_KEY, ['table', 'board'], 'table'));
// "Ver OS da máquina" (?machine=) abre sempre a lista, que filtra pela máquina
const showBoard = computed(
  () => tab.value === 'os' && osMode.value === 'board' && !route.query.machine
);
const fills = computed(
  () => (kind.value && !showBoard.value) || tab.value === 'produtos'
);

const setMode = value => {
  osMode.value = value;
  remember(MODE_KEY, value);
};
const setNotesMode = value => {
  notesMode.value = value;
  remember(NOTES_KEY, value);
};

const clientDialog = ref(null);

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
        <div class="pt-5 mx-auto max-w-[110rem]">
          <div class="flex flex-wrap items-end justify-between gap-3">
            <div class="flex flex-col gap-0.5 min-w-0">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('OUTSIDER_ERP.TITLE') }}
                <template v-if="currentGroup">
                  · {{ t(currentGroup.label) }}
                </template>
              </span>
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                <h1 class="mb-0 text-xl font-medium text-n-slate-12">
                  {{
                    currentReport
                      ? t(currentReport.label)
                      : tab
                        ? t(`OUTSIDER_ERP.TABS.${tab.toUpperCase()}`)
                        : t('OUTSIDER_ERP.SIDEBAR')
                  }}
                </h1>
                <Button
                  v-if="erpState.canRegisterClient"
                  size="xs"
                  variant="faded"
                  color="teal"
                  icon="i-lucide-user-plus"
                  :label="t('OUTSIDER_ERP.CLIENT.NEW')"
                  @click="clientDialog?.open()"
                />
              </div>
            </div>
            <nav
              v-if="groups.length > 1"
              class="flex items-center max-w-full gap-1 p-1 overflow-x-auto rounded-xl bg-n-alpha-2"
              data-erp-groups
            >
              <button
                v-for="group in groups"
                :key="group.key"
                type="button"
                class="flex items-center gap-2 h-9 px-3.5 text-[13px] rounded-lg whitespace-nowrap"
                :class="
                  currentGroup?.key === group.key
                    ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                    : 'text-n-slate-11 hover:text-n-slate-12'
                "
                :title="t(group.label)"
                @click="goGroup(group)"
              >
                <Icon :icon="group.icon" class="size-4" />
                <span
                  :class="
                    currentGroup?.key === group.key
                      ? 'inline'
                      : 'hidden md:inline'
                  "
                >
                  {{ t(group.label) }}
                </span>
              </button>
            </nav>
          </div>
          <div
            v-if="currentGroup"
            class="flex flex-wrap items-center justify-between mt-3 border-b gap-x-3 border-n-weak"
          >
            <nav
              class="flex items-center gap-1 -mb-px overflow-x-auto"
              data-erp-tabs
            >
              <button
                v-for="item in currentGroup.items"
                :key="item.name"
                type="button"
                class="flex items-center gap-1.5 h-10 px-3 text-[13px] border-b-2 whitespace-nowrap"
                :class="
                  tab === item.name
                    ? 'border-n-brand text-n-slate-12 font-medium'
                    : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
                "
                @click="go(item.name)"
              >
                <Icon :icon="item.icon" class="size-4" />
                {{ t(item.label) }}
              </button>
            </nav>
            <div class="flex items-center gap-2 py-1.5">
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
                    :icon="
                      mode === 'board' ? 'i-lucide-kanban' : 'i-lucide-list'
                    "
                    class="size-3.5"
                  />
                  {{
                    t(
                      `OUTSIDER_ERP.RECORDS.ORDERS.${mode === 'board' ? 'BOARD' : 'TABLE'}`
                    )
                  }}
                </button>
              </div>
              <div
                v-if="tab === 'notas'"
                class="flex items-center p-0.5 rounded-lg bg-n-alpha-2"
              >
                <button
                  v-for="mode in NOTE_KINDS"
                  :key="mode"
                  type="button"
                  class="flex items-center gap-1.5 h-7 px-2.5 text-xs rounded-md whitespace-nowrap"
                  :class="
                    notesMode === mode
                      ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                      : 'text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="setNotesMode(mode)"
                >
                  <Icon
                    :icon="
                      mode === 'invoices'
                        ? 'i-lucide-package'
                        : 'i-lucide-hammer'
                    "
                    class="size-3.5"
                  />
                  {{
                    t(
                      `OUTSIDER_ERP.RECORDS.${mode === 'invoices' ? 'INVOICES' : 'SERVICE_INVOICES'}.MODE`
                    )
                  }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </header>
      <main
        class="flex-1 min-h-0 px-4 pt-4 sm:px-6"
        :class="
          fills ? 'overflow-y-auto md:overflow-hidden' : 'overflow-y-auto'
        "
      >
        <div
          class="w-full mx-auto max-w-[110rem]"
          :class="fills ? 'md:h-full pb-4 md:pb-0' : 'pb-8'"
        >
          <div
            v-if="crash"
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-ruby-2"
          >
            <Icon
              icon="i-lucide-triangle-alert"
              class="size-8 text-n-ruby-11"
            />
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
          <ErpProducts v-else-if="tab === 'produtos'" />
          <component
            :is="currentReport.report.component"
            v-else-if="currentReport"
            :key="currentReport.name"
          />
          <ErpPrints v-else-if="tab === 'modelos'" />
          <ErpSettings v-else-if="tab === 'settings'" />
          <div
            v-else
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
          </div>
        </div>
      </main>
    </div>
    <ErpClientDialog ref="clientDialog" />
  </section>
</template>
