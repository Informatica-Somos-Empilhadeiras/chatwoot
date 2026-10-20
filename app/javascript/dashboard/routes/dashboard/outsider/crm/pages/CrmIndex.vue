<script setup>
// OUTSIDER: CRM de vendas (ver app/controllers/api/v1/accounts/outsider/crm/).
// Quem não é administrador só entra se for membro de alguma unidade comercial. A seção vem da rota
// (crm/:tab), escolhida pelos subitens do CRM no menu lateral.
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OpportunityList from '../components/OpportunityList.vue';
import TasksPanel from '../components/TasksPanel.vue';
import CrmSettingsPanel from '../components/settings/CrmSettingsPanel.vue';
import ReportsPanel from '../components/reports/ReportsPanel.vue';
import GoalsPanel from '../components/goals/GoalsPanel.vue';
import { errorMessage } from '../helpers';
import { crmSections } from '../sections';
import {
  crmState,
  invalidateCrmContext,
  refreshMyTasks,
  startTaskReminders,
} from '../crmStore';

const { t } = useI18n();
const route = useRoute();

const isLoading = ref(true);
const access = ref({ enabled: false, administrator: false, units: [] });
const units = ref([]);
const pipelines = ref([]);

// as seções ficam no menu lateral do Chatwoot (sidebar.js); aqui só o título da seção aberta
const sections = computed(() => crmSections(access.value));

const activeTab = computed(() =>
  sections.value.some(section => section.key === route.params.tab)
    ? route.params.tab
    : 'opportunities'
);

const activeSection = computed(() =>
  sections.value.find(section => section.key === activeTab.value)
);

const loadStructure = async () => {
  const [unitsResponse, pipelinesResponse] = await Promise.all([
    CrmAPI.getUnits(),
    CrmAPI.getPipelines(),
  ]);
  units.value = unitsResponse.data;
  pipelines.value = pipelinesResponse.data;
};

const reload = async () => {
  invalidateCrmContext();
  try {
    const { data } = await CrmAPI.getAccess();
    access.value = data;
    // o menu lateral usa o mesmo acesso (seção Configurações, por exemplo)
    crmState.access = data;
    if (data.enabled) await loadStructure();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

onMounted(async () => {
  await reload();
  isLoading.value = false;
  if (access.value.enabled) {
    refreshMyTasks();
    startTaskReminders(t);
  }
});
</script>

<template>
  <section class="flex w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex flex-col w-full h-full">
      <header class="px-6">
        <div
          class="flex flex-wrap items-center justify-between w-full gap-3 pt-6 pb-4 mx-auto"
          :class="
            activeTab === 'opportunities' ? 'max-w-[110rem]' : 'max-w-6xl'
          "
        >
          <div class="flex flex-col min-w-0 gap-0.5">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('OUTSIDER_CRM.TITLE') }}
            </span>
            <span class="text-xl font-medium truncate text-n-slate-12">
              {{
                access.enabled && activeSection
                  ? t(activeSection.label)
                  : t('OUTSIDER_CRM.SIDEBAR')
              }}
            </span>
          </div>
        </div>
      </header>

      <main class="flex-1 px-6 overflow-y-auto">
        <div
          class="w-full pb-8 mx-auto"
          :class="
            activeTab === 'opportunities' ? 'max-w-[110rem]' : 'max-w-6xl'
          "
        >
          <div v-if="isLoading" class="flex justify-center p-8">
            <Spinner class="text-n-slate-10" />
          </div>
          <div
            v-else-if="!access.enabled"
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
          >
            <Icon icon="i-lucide-handshake" class="size-10 text-n-slate-9" />
            <p class="max-w-md mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_CRM.STATES.NO_ACCESS') }}
            </p>
          </div>
          <template v-else>
            <OpportunityList
              v-if="activeTab === 'opportunities'"
              :access="access"
              :units="units"
              :pipelines="pipelines"
            />
            <TasksPanel
              v-else-if="activeTab === 'tasks'"
              :access="access"
              :pipelines="pipelines"
            />
            <GoalsPanel v-else-if="activeTab === 'goals'" :access="access" />
            <ReportsPanel
              v-else-if="activeTab === 'reports'"
              :access="access"
              :units="units"
              :pipelines="pipelines"
            />
            <CrmSettingsPanel
              v-else
              :access="access"
              :units="units"
              :pipelines="pipelines"
              @changed="reload"
            />
          </template>
        </div>
      </main>
    </div>
  </section>
</template>
