<script setup>
// OUTSIDER: tela de negócios. Indicadores no topo, filtros compartilhados e duas visualizações:
// Kanban (um pipeline por vez, só negócios abertos) e tabela (com ordenação e exportação CSV).
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import OpportunityDialog from './OpportunityDialog.vue';
import OpportunityDrawer from './OpportunityDrawer.vue';
import KanbanBoard from './KanbanBoard.vue';
import MetricsBar from './MetricsBar.vue';
import {
  STATUS_COLORS,
  errorMessage,
  formatDate,
  formatMoney,
} from '../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
});

const VIEW_KEY = 'outsiderCrmView';

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const readView = () => {
  try {
    return localStorage.getItem(VIEW_KEY) === 'table' ? 'table' : 'board';
  } catch {
    return 'board';
  }
};

const dialogRef = ref(null);
const drawerRef = ref(null);
const boardRef = ref(null);
const isLoading = ref(false);
const isExporting = ref(false);
const view = ref(readView());
const opportunities = ref([]);
const lostReasons = ref([]);
const refreshKey = ref(0);
const meta = ref({ count: 0, page: 1, per_page: 50 });
const searchText = ref('');
const filters = ref({
  business_unit_id: '',
  pipeline_id: '',
  status: 'open',
  owner_id: '',
  period: 'month',
  sort: 'recent',
  q: '',
});

const isBoard = computed(() => view.value === 'board');

const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_UNITS') },
  ...props.units.map(unit => ({ value: unit.id, label: unit.name })),
]);

const visiblePipelines = computed(() =>
  props.pipelines.filter(
    pipeline =>
      (pipeline.active || pipeline.id === filters.value.pipeline_id) &&
      (!filters.value.business_unit_id ||
        pipeline.business_unit_id === filters.value.business_unit_id)
  )
);

const pipelineOptions = computed(() => [
  ...(isBoard.value
    ? []
    : [{ value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_PIPELINES') }]),
  ...visiblePipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  })),
]);

const boardPipeline = computed(() =>
  props.pipelines.find(pipeline => pipeline.id === filters.value.pipeline_id)
);

const statusOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_STATUS') },
  ...['open', 'won', 'lost', 'forwarded'].map(status => ({
    value: status,
    label: t(`OUTSIDER_CRM.STATUS.${status.toUpperCase()}`),
  })),
]);

const managesAnyUnit = computed(
  () =>
    props.access.administrator ||
    props.access.units.some(unit => unit.role === 'manager')
);

const ownerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_OWNERS') },
  { value: currentUser.value.id, label: t('OUTSIDER_CRM.FILTERS.MINE') },
  ...(managesAnyUnit.value
    ? agents.value
        .filter(agent => agent.id !== currentUser.value.id)
        .map(agent => ({ value: agent.id, label: agent.name }))
    : []),
]);

const periodOptions = computed(() =>
  ['month', 'quarter', 'year'].map(value => ({
    value,
    label: t(`OUTSIDER_CRM.METRICS.PERIODS.${value.toUpperCase()}`),
  }))
);

const sortOptions = computed(() =>
  ['recent', 'value', 'close', 'created'].map(value => ({
    value,
    label: t(`OUTSIDER_CRM.SORT.${value.toUpperCase()}`),
  }))
);

const stageNames = computed(() =>
  Object.fromEntries(
    props.pipelines.flatMap(pipeline =>
      pipeline.stages.map(stage => [stage.id, stage])
    )
  )
);

const unitNames = computed(() =>
  props.units.length > 1
    ? Object.fromEntries(props.units.map(unit => [unit.id, unit.name]))
    : {}
);

const totalValue = computed(() =>
  opportunities.value.reduce((sum, item) => sum + item.value_cents, 0)
);

const pageCount = computed(() =>
  Math.max(1, Math.ceil(meta.value.count / meta.value.per_page))
);

const tableParams = (extra = {}) =>
  Object.fromEntries(
    Object.entries({ ...filters.value, period: undefined, ...extra }).filter(
      ([, v]) => v !== '' && v !== undefined
    )
  );

const load = async (page = 1) => {
  if (isBoard.value) return;
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getOpportunities(tableParams({ page }));
    opportunities.value = data.payload;
    meta.value = data.meta;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const exportCsv = async () => {
  isExporting.value = true;
  try {
    const { data } = await CrmAPI.exportOpportunities(tableParams());
    const today = new Date().toISOString().slice(0, 10);
    downloadCsvFile(`negocios-${today}.csv`, data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isExporting.value = false;
  }
};

// o Kanban mostra um pipeline por vez: escolhe o primeiro visível quando não há nenhum
const ensureBoardPipeline = () => {
  if (!isBoard.value || boardPipeline.value) return;
  filters.value.pipeline_id = visiblePipelines.value[0]?.id ?? '';
};

const setView = value => {
  view.value = value;
  try {
    localStorage.setItem(VIEW_KEY, value);
  } catch {
    // sem localStorage a escolha vale só nesta visita
  }
  ensureBoardPipeline();
  load(1);
};

const refresh = () => {
  refreshKey.value += 1;
  if (isBoard.value) boardRef.value?.reload();
  else load(meta.value.page);
};

const applySearch = useDebounceFn(() => {
  filters.value.q = searchText.value.trim();
}, 300);

watch(searchText, applySearch);
watch(
  () => ({ ...filters.value, period: undefined }),
  () => load(1),
  { deep: true }
);
watch(
  () => filters.value.business_unit_id,
  () => {
    filters.value.pipeline_id = '';
    ensureBoardPipeline();
  }
);
watch(() => props.pipelines, ensureBoardPipeline);

const openNew = () => dialogRef.value?.open();
const openEdit = opportunity => dialogRef.value?.open(opportunity);
// clicar num negócio abre o painel (tarefas, linha do tempo, auditoria); de lá se edita
const openDetails = opportunity => drawerRef.value?.open(opportunity);
const onSaved = () => {
  refresh();
  drawerRef.value?.refresh();
};
const openNewInStage = stage =>
  dialogRef.value?.open(null, {
    business_unit_id: boardPipeline.value.business_unit_id,
    pipeline_id: stage.pipeline_id,
    stage_id: stage.id,
  });

onMounted(async () => {
  ensureBoardPipeline();
  load(1);
  store.dispatch('agents/get');
  try {
    const { data } = await CrmAPI.getLostReasons();
    lostReasons.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <div
        class="flex p-0.5 rounded-lg bg-n-alpha-2 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <Button
          v-for="option in ['board', 'table']"
          :key="option"
          type="button"
          size="sm"
          :icon="
            option === 'board' ? 'i-lucide-square-kanban' : 'i-lucide-table'
          "
          :variant="view === option ? 'solid' : 'ghost'"
          :color="view === option ? 'blue' : 'slate'"
          :label="t(`OUTSIDER_CRM.VIEWS.${option.toUpperCase()}`)"
          @click="setView(option)"
        />
      </div>
      <Input
        v-model="searchText"
        type="search"
        :placeholder="t('OUTSIDER_CRM.FILTERS.SEARCH')"
        :custom-input-class="['h-8 ltr:!pl-8 rtl:!pr-8 !py-1']"
        class="w-full sm:w-56"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
          />
        </template>
      </Input>
      <Select
        v-if="units.length > 1"
        v-model="filters.business_unit_id"
        :options="unitOptions"
      />
      <Select v-model="filters.pipeline_id" :options="pipelineOptions" />
      <Select
        v-if="!isBoard"
        v-model="filters.status"
        :options="statusOptions"
      />
      <Select v-model="filters.owner_id" :options="ownerOptions" />
      <Select
        v-model="filters.period"
        v-tooltip="t('OUTSIDER_CRM.METRICS.PERIOD')"
        :options="periodOptions"
      />
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      <div class="flex-1" />
      <Button
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.OPPORTUNITY.NEW')"
        :disabled="!pipelines.length"
        @click="openNew"
      />
    </div>

    <p
      v-if="!pipelines.length"
      class="p-3 mb-0 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
    >
      {{ t('OUTSIDER_CRM.STATES.NO_PIPELINES') }}
    </p>

    <MetricsBar
      v-if="pipelines.length"
      :filters="filters"
      :refresh-key="refreshKey"
    />

    <KanbanBoard
      v-if="isBoard && boardPipeline"
      ref="boardRef"
      :access="access"
      :pipeline="boardPipeline"
      :filters="filters"
      :lost-reasons="lostReasons"
      @open="openDetails"
      @new="openNewInStage"
      @changed="refreshKey += 1"
    />

    <template v-if="!isBoard">
      <div class="flex flex-wrap items-center justify-end gap-2">
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.SORT.LABEL') }}
        </span>
        <Select v-model="filters.sort" :options="sortOptions" />
        <Button
          type="button"
          icon="i-lucide-download"
          size="sm"
          variant="faded"
          color="slate"
          :label="t('OUTSIDER_CRM.TABLE.EXPORT')"
          :is-loading="isExporting"
          :disabled="!meta.count"
          @click="exportCsv"
        />
      </div>

      <div
        class="overflow-x-auto outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <table class="w-full text-sm min-w-[56rem]">
          <thead>
            <tr
              class="text-xs text-left border-b text-n-slate-11 border-n-weak"
            >
              <th class="px-4 py-3 font-medium">
                {{ t('OUTSIDER_CRM.TABLE.OPPORTUNITY') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('OUTSIDER_CRM.TABLE.CONTACT') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('OUTSIDER_CRM.TABLE.STAGE') }}
              </th>
              <th class="px-4 py-3 font-medium text-right">
                {{ t('OUTSIDER_CRM.TABLE.VALUE') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('OUTSIDER_CRM.TABLE.CLOSE_DATE') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('OUTSIDER_CRM.TABLE.OWNER') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('OUTSIDER_CRM.TABLE.STATUS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="!opportunities.length && !isLoading">
              <td colspan="7" class="px-4 py-10 text-center text-n-slate-11">
                {{ t('OUTSIDER_CRM.STATES.EMPTY') }}
              </td>
            </tr>
            <tr
              v-for="opportunity in opportunities"
              :key="opportunity.id"
              class="border-b cursor-pointer border-n-weak last:border-0 hover:bg-n-alpha-1"
              @click="openDetails(opportunity)"
            >
              <td class="px-4 py-3">
                <div class="flex flex-col min-w-0">
                  <span class="font-medium truncate text-n-slate-12">
                    {{ opportunity.title }}
                  </span>
                  <span class="text-xs text-n-slate-11">
                    {{ opportunity.code }}
                    <template v-if="unitNames[opportunity.business_unit_id]">
                      · {{ unitNames[opportunity.business_unit_id] }}
                    </template>
                    <span
                      v-if="opportunity.tasks?.overdue"
                      class="font-medium text-n-ruby-11"
                    >
                      ·
                      {{
                        t('OUTSIDER_CRM.BOARD.TASKS_LATE', {
                          count: opportunity.tasks.overdue,
                        })
                      }}
                    </span>
                  </span>
                </div>
              </td>
              <td class="px-4 py-3">
                <div class="flex items-center min-w-0 gap-2">
                  <Avatar
                    :name="opportunity.contact.name"
                    :src="opportunity.contact.thumbnail"
                    :size="24"
                    rounded-full
                  />
                  <span class="truncate text-n-slate-12">
                    {{ opportunity.contact.name }}
                  </span>
                </div>
              </td>
              <td class="px-4 py-3">
                <span class="inline-flex items-center gap-1.5 text-n-slate-12">
                  <span
                    class="rounded-full size-2"
                    :style="{
                      backgroundColor:
                        stageNames[opportunity.stage_id]?.color || '#64748B',
                    }"
                  />
                  {{ stageNames[opportunity.stage_id]?.name }}
                  <Icon
                    v-if="opportunity.sla_exceeded"
                    v-tooltip="t('OUTSIDER_CRM.BOARD.SLA')"
                    icon="i-lucide-clock-alert"
                    class="size-3.5 text-n-amber-11"
                  />
                </span>
              </td>
              <td class="px-4 py-3 font-medium text-right text-n-slate-12">
                {{ formatMoney(opportunity.value_cents) }}
              </td>
              <td
                class="px-4 py-3"
                :class="
                  opportunity.overdue ? 'text-n-ruby-11' : 'text-n-slate-11'
                "
              >
                {{ formatDate(opportunity.expected_close_on) }}
              </td>
              <td class="px-4 py-3 text-n-slate-11">
                {{ opportunity.owner?.name }}
              </td>
              <td class="px-4 py-3">
                <span
                  class="px-2 py-0.5 text-xs rounded-md"
                  :class="STATUS_COLORS[opportunity.status]"
                >
                  {{
                    t(`OUTSIDER_CRM.STATUS.${opportunity.status.toUpperCase()}`)
                  }}
                </span>
                <span
                  v-if="opportunity.forwarded_to"
                  class="block mt-0.5 text-xs text-n-slate-10"
                >
                  {{
                    t('OUTSIDER_CRM.FORWARD.TO_UNIT', {
                      unit: opportunity.forwarded_to.business_unit_name,
                    })
                  }}
                </span>
                <span
                  v-else-if="opportunity.forwarded_from"
                  class="block mt-0.5 text-xs text-n-slate-10"
                >
                  {{
                    t('OUTSIDER_CRM.FORWARD.FROM_UNIT', {
                      unit: opportunity.forwarded_from.business_unit_name,
                    })
                  }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        class="flex flex-wrap items-center justify-between gap-2 text-sm text-n-slate-11"
      >
        <span>
          {{
            t('OUTSIDER_CRM.TABLE.SUMMARY', {
              count: meta.count,
              total: formatMoney(totalValue),
            })
          }}
        </span>
        <div v-if="pageCount > 1" class="flex items-center gap-2">
          <Button
            icon="i-lucide-chevron-left"
            size="xs"
            variant="ghost"
            color="slate"
            :disabled="meta.page <= 1"
            @click="load(meta.page - 1)"
          />
          <span>{{ meta.page }} / {{ pageCount }}</span>
          <Button
            icon="i-lucide-chevron-right"
            size="xs"
            variant="ghost"
            color="slate"
            :disabled="meta.page >= pageCount"
            @click="load(meta.page + 1)"
          />
        </div>
      </div>
    </template>

    <OpportunityDialog
      ref="dialogRef"
      :access="access"
      :pipelines="pipelines"
      :agents="agents"
      @saved="onSaved"
    />
    <OpportunityDrawer
      ref="drawerRef"
      :access="access"
      :pipelines="pipelines"
      @edit="openEdit"
      @changed="refresh"
    />
  </div>
</template>
