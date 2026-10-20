<script setup>
// OUTSIDER: CRM de vendas (ver app/controllers/api/v1/accounts/outsider/crm/).
// Quem não é administrador só entra se for membro de alguma unidade comercial.
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OpportunityList from '../components/OpportunityList.vue';
import TasksPanel from '../components/TasksPanel.vue';
import CrmSettingsPanel from '../components/settings/CrmSettingsPanel.vue';
import ReportsPanel from '../components/reports/ReportsPanel.vue';
import { errorMessage } from '../helpers';
import {
  crmState,
  invalidateCrmContext,
  refreshMyTasks,
  startTaskReminders,
} from '../crmStore';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const isLoading = ref(true);
const access = ref({ enabled: false, administrator: false, units: [] });
const units = ref([]);
const pipelines = ref([]);

const canConfigure = computed(
  () =>
    access.value.administrator ||
    access.value.units.some(unit => unit.role === 'manager')
);

const tabs = computed(() => [
  { key: 'opportunities', label: t('OUTSIDER_CRM.TABS.OPPORTUNITIES') },
  {
    key: 'tasks',
    label: t('OUTSIDER_CRM.TABS.TASKS'),
    count: crmState.myTasks.pending || undefined,
  },
  { key: 'reports', label: t('OUTSIDER_CRM.TABS.REPORTS') },
  ...(canConfigure.value
    ? [{ key: 'settings', label: t('OUTSIDER_CRM.TABS.SETTINGS') }]
    : []),
]);

const activeTab = computed(() =>
  tabs.value.some(tab => tab.key === route.params.tab)
    ? route.params.tab
    : 'opportunities'
);

const changeTab = tab => {
  router.replace({ params: { ...route.params, tab: tab.key } });
};

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
          <span class="text-xl font-medium truncate text-n-slate-12">
            {{ t('OUTSIDER_CRM.TITLE') }}
          </span>
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
            <div class="p-px mb-6 overflow-x-auto">
              <TabBar
                :tabs="tabs"
                :initial-active-tab="
                  tabs.findIndex(tab => tab.key === activeTab)
                "
                @tab-changed="changeTab"
              />
            </div>
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
