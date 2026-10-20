<script setup>
// OUTSIDER: aba Tarefas do CRM. Mostra as tarefas do usuário (ou de outro responsável, ou de
// todos, sempre só das unidades que ele enxerga), agrupadas por prazo. Clicar abre o negócio.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import { useCrmChanges } from '../live';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import OpportunityDrawer from './OpportunityDrawer.vue';
import OpportunityDialog from './OpportunityDialog.vue';
import { refreshMyTasks } from '../crmStore';
import { errorMessage, formatDateTime, taskKindIcon } from '../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  pipelines: { type: Array, required: true },
});

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');

const drawerRef = ref(null);
const dialogRef = ref(null);
const isLoading = ref(false);
const busyId = ref(null);
const tasks = ref([]);
const meta = ref({ pending: 0, overdue: 0 });
const filters = ref({
  assignee_id: 'me',
  status: 'pending',
  business_unit_id: '',
});

const canSeeOthers = computed(
  () =>
    props.access.administrator ||
    props.access.units.some(unit => unit.role === 'manager')
);

const assigneeOptions = computed(() => [
  { value: 'me', label: t('OUTSIDER_CRM.TASKS.FILTERS.MINE') },
  { value: 'all', label: t('OUTSIDER_CRM.TASKS.FILTERS.ALL') },
  ...(canSeeOthers.value
    ? agents.value.map(agent => ({ value: agent.id, label: agent.name }))
    : []),
]);

const statusOptions = computed(() => [
  { value: 'pending', label: t('OUTSIDER_CRM.TASKS.FILTERS.PENDING') },
  { value: 'done', label: t('OUTSIDER_CRM.TASKS.FILTERS.DONE') },
]);

const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.FILTERS.ALL_UNITS') },
  ...props.access.units.map(unit => ({ value: unit.id, label: unit.name })),
]);

const dayStart = offset => {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  date.setDate(date.getDate() + offset);
  return date.getTime();
};

const groupOf = task => {
  if (filters.value.status === 'done') return 'done';
  if (!task.due_at) return 'no_date';
  const due = new Date(task.due_at).getTime();
  if (task.overdue) return 'overdue';
  if (due < dayStart(1)) return 'today';
  if (due < dayStart(2)) return 'tomorrow';
  if (due < dayStart(8)) return 'week';
  return 'later';
};

const GROUPS = [
  'overdue',
  'today',
  'tomorrow',
  'week',
  'later',
  'no_date',
  'done',
];

const groups = computed(() =>
  GROUPS.map(key => ({
    key,
    tasks: tasks.value.filter(task => groupOf(task) === key),
  })).filter(group => group.tasks.length)
);

// options.silent: recarga ao vivo, sem o indicador de carregando
const load = async options => {
  if (!options?.silent) isLoading.value = true;
  try {
    const { data } = await CrmAPI.getTaskList(filters.value);
    tasks.value = data.payload;
    meta.value = data.meta;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const reload = () => {
  load();
  refreshMyTasks();
};

const toggle = async task => {
  busyId.value = task.id;
  try {
    await CrmAPI.updateTask(task.opportunity_id, task.id, {
      completed: !task.completed_at,
    });
    useAlert(
      task.completed_at
        ? t('OUTSIDER_CRM.TASKS.REOPENED')
        : t('OUTSIDER_CRM.TASKS.COMPLETED', { title: task.title })
    );
    reload();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    busyId.value = null;
  }
};

const openOpportunity = async task => {
  try {
    const { data } = await CrmAPI.getOpportunity(task.opportunity_id);
    drawerRef.value?.open(data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const onSaved = () => {
  drawerRef.value?.refresh();
  reload();
};

watch(filters, () => load(), { deep: true });

// alguém criou, concluiu ou mudou uma tarefa (ou o negócio dela): a lista recarrega na hora
useCrmChanges(changes => {
  if (changes.some(change => change.kind !== 'config')) load({ silent: true });
});

onMounted(() => {
  load();
  if (!agents.value.length) store.dispatch('agents/get');
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <Select v-model="filters.assignee_id" :options="assigneeOptions" />
      <Select v-model="filters.status" :options="statusOptions" />
      <Select
        v-if="access.units.length > 1"
        v-model="filters.business_unit_id"
        :options="unitOptions"
      />
      <div class="flex-1" />
      <span class="flex items-center gap-3 text-sm text-n-slate-11">
        <span>{{
          t('OUTSIDER_CRM.TASKS.PENDING_COUNT', { count: meta.pending })
        }}</span>
        <span v-if="meta.overdue" class="font-medium text-n-ruby-11">
          {{ t('OUTSIDER_CRM.TASKS.OVERDUE_COUNT', { count: meta.overdue }) }}
        </span>
      </span>
    </div>

    <div v-if="isLoading && !tasks.length" class="flex justify-center p-8">
      <Spinner class="text-n-slate-10" />
    </div>

    <div
      v-else-if="!tasks.length"
      class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
    >
      <Icon icon="i-lucide-list-checks" class="size-10 text-n-slate-9" />
      <p class="max-w-md mb-0 text-sm text-n-slate-11">
        {{
          filters.status === 'done'
            ? t('OUTSIDER_CRM.TASKS.LIST_EMPTY_DONE')
            : t('OUTSIDER_CRM.TASKS.LIST_EMPTY')
        }}
      </p>
    </div>

    <section
      v-for="group in groups"
      :key="group.key"
      class="flex flex-col gap-2"
    >
      <h3
        class="flex items-center gap-2 mb-0 text-sm font-medium"
        :class="group.key === 'overdue' ? 'text-n-ruby-11' : 'text-n-slate-12'"
      >
        {{ t(`OUTSIDER_CRM.TASKS.GROUPS.${group.key.toUpperCase()}`) }}
        <span class="text-xs font-normal text-n-slate-10">
          {{ group.tasks.length }}
        </span>
      </h3>
      <ul
        class="flex flex-col mb-0 overflow-hidden list-none divide-y rounded-xl divide-n-weak bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <li
          v-for="task in group.tasks"
          :key="task.id"
          class="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-n-alpha-1"
          @click="openOpportunity(task)"
        >
          <button
            type="button"
            class="flex items-center justify-center border rounded-full size-5 shrink-0 disabled:cursor-default"
            :class="
              task.completed_at
                ? 'bg-n-teal-9 border-n-teal-9 text-white'
                : 'border-n-slate-8 enabled:hover:border-n-teal-9 enabled:hover:bg-n-teal-3'
            "
            :disabled="!task.can_complete || busyId === task.id"
            :title="
              task.completed_at
                ? t('OUTSIDER_CRM.TASKS.REOPEN')
                : t('OUTSIDER_CRM.TASKS.COMPLETE')
            "
            @click.stop="toggle(task)"
          >
            <Icon
              v-if="task.completed_at"
              icon="i-lucide-check"
              class="size-3"
            />
          </button>
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="flex items-center gap-1.5 text-sm text-n-slate-12">
              <Icon
                :icon="taskKindIcon(task.kind)"
                class="size-3.5 shrink-0 text-n-slate-10"
              />
              <span
                class="truncate"
                :class="{ 'line-through text-n-slate-10': task.completed_at }"
              >
                {{ task.title }}
              </span>
            </span>
            <span class="text-xs truncate text-n-slate-11">
              {{ task.opportunity.code }} · {{ task.opportunity.title }}
            </span>
          </div>
          <span
            class="items-center hidden gap-1.5 min-w-0 text-sm sm:flex w-48 text-n-slate-11"
          >
            <Avatar
              :name="task.opportunity.contact?.name || ''"
              :src="task.opportunity.contact?.thumbnail"
              :size="20"
              rounded-full
            />
            <span class="truncate">{{ task.opportunity.contact?.name }}</span>
          </span>
          <span
            v-if="filters.assignee_id !== 'me'"
            class="hidden w-32 text-xs truncate md:block text-n-slate-11"
          >
            {{ task.assignee?.name || '—' }}
          </span>
          <span
            class="text-xs text-right w-28 shrink-0"
            :class="
              task.overdue ? 'font-medium text-n-ruby-11' : 'text-n-slate-11'
            "
          >
            {{
              task.completed_at
                ? formatDateTime(task.completed_at, t)
                : formatDateTime(task.due_at, t) || '—'
            }}
          </span>
        </li>
      </ul>
    </section>

    <OpportunityDrawer
      ref="drawerRef"
      :access="access"
      :pipelines="pipelines"
      @edit="opportunity => dialogRef?.open(opportunity)"
      @changed="reload"
    />
    <OpportunityDialog
      ref="dialogRef"
      :access="access"
      :pipelines="pipelines"
      :agents="agents"
      @saved="onSaved"
    />
  </div>
</template>
