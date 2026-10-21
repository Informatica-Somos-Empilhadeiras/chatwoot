<script setup>
// OUTSIDER: CRM de vendas (ver app/controllers/api/v1/accounts/outsider/crm/).
// O CRM precisa estar ligado na conta (Super Admin) e para a pessoa (Configurações > Acesso); quem
// não é administrador também precisa ser membro de alguma unidade comercial. A seção vem da rota
// (crm/:tab), escolhida pelos subitens do CRM no menu lateral.
import { ref, computed, watch, onMounted } from 'vue';
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
  ensureCrmContext,
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

const showStructure = async () => {
  if (!access.value.enabled) return;
  try {
    await loadStructure();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

// o acesso é o mesmo do menu lateral (crmStore): buscado de novo depois de mudar configurações
const reload = async () => {
  invalidateCrmContext();
  await ensureCrmContext();
  access.value = crmState.access;
  await showStructure();
};

// CRM ligado ou desligado na conta ou para alguém, ou unidades mudadas, com a tela aberta: o crmStore
// confere o acesso pelo aviso ao vivo e a tela acompanha
watch(
  () => crmState.access,
  value => {
    if (isLoading.value || value === access.value) return;
    access.value = value;
    showStructure();
  }
);

// por que a pessoa não entra: CRM desligado na conta, desligado para ela ou fora das unidades
const noAccessMessage = computed(() => {
  const key = {
    account: 'NO_ACCESS_ACCOUNT',
    agent: 'NO_ACCESS_AGENT',
  }[access.value.reason];
  return t(`OUTSIDER_CRM.STATES.${key || 'NO_ACCESS'}`);
});

onMounted(async () => {
  await reload();
  // conferência ao vivo que chegou enquanto a tela carregava (o watch acima ainda não olhava)
  if (crmState.access !== access.value) {
    access.value = crmState.access;
    await showStructure();
  }
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
              {{ noAccessMessage }}
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
