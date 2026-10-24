<script setup>
// OUTSIDER: tarefas de um negócio (aba CRM da conversa e painel do negócio na tela do CRM).
// Pendentes primeiro, por prazo, com a atrasada em vermelho. Concluir, adiar e apagar na lista.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import TaskForm from './TaskForm.vue';
import LoadError from './LoadError.vue';
import {
  combineDateTime,
  errorMessage,
  formatDateTime,
  taskKindIcon,
  toDateInput,
  toTimeInput,
} from '../helpers';

const props = defineProps({
  opportunity: { type: Object, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();

const tasks = ref([]);
const isLoading = ref(false);
const loadError = ref('');
const showForm = ref(false);
const showDone = ref(false);
const menuFor = ref(null);
const busyId = ref(null);
const postponing = ref(null);
const postponeForm = ref({ date: '', time: '' });

const pending = computed(() => tasks.value.filter(task => !task.completed_at));
const done = computed(() => tasks.value.filter(task => task.completed_at));

const load = async () => {
  isLoading.value = !tasks.value.length;
  try {
    const { data } = await CrmAPI.getTasks(props.opportunity.id);
    tasks.value = data;
    loadError.value = '';
  } catch (error) {
    loadError.value = errorMessage(t, error);
  } finally {
    isLoading.value = false;
  }
};

const changed = async message => {
  if (message) useAlert(message);
  await load();
  emit('changed');
};

const onCreated = task => {
  showForm.value = false;
  changed(t('OUTSIDER_CRM.TASKS.CREATED', { title: task.title }));
};

const update = async (task, attributes, message) => {
  busyId.value = task.id;
  try {
    await CrmAPI.updateTask(props.opportunity.id, task.id, attributes);
    await changed(message);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    busyId.value = null;
  }
};

const toggle = task =>
  update(
    task,
    { completed: !task.completed_at },
    task.completed_at
      ? t('OUTSIDER_CRM.TASKS.REOPENED')
      : t('OUTSIDER_CRM.TASKS.COMPLETED', { title: task.title })
  );

// adiar parte do prazo atual (ou de agora, se já passou), mantendo a hora quando faz sentido
const postponeTo = (task, option) => {
  const now = new Date();
  const due = task.due_at ? new Date(task.due_at) : null;
  const base = due && due > now ? due : now;
  const next = new Date(base);
  if (option === 'hour') {
    next.setTime(now.getTime() + 60 * 60 * 1000);
  } else if (option === 'tomorrow') {
    next.setTime(now.getTime());
    next.setDate(now.getDate() + 1);
    next.setHours(due ? due.getHours() : 9, due ? due.getMinutes() : 0, 0, 0);
  } else {
    next.setDate(base.getDate() + 7);
  }
  return next;
};

const postpone = (task, date) =>
  update(
    task,
    { due_at: date.toISOString() },
    t('OUTSIDER_CRM.TASKS.POSTPONED', {
      date: formatDateTime(date.toISOString(), t),
    })
  );

const remove = async task => {
  busyId.value = task.id;
  try {
    await CrmAPI.deleteTask(props.opportunity.id, task.id);
    await changed(t('OUTSIDER_CRM.TASKS.DELETED'));
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    busyId.value = null;
  }
};

const menuItems = task => {
  const items = [];
  if (!task.completed_at && task.can_complete) {
    ['hour', 'tomorrow', 'week'].forEach(option =>
      items.push({
        action: `postpone_${option}`,
        value: option,
        label: t(`OUTSIDER_CRM.TASKS.POSTPONE.${option.toUpperCase()}`),
        icon: 'i-lucide-alarm-clock',
      })
    );
    items.push({
      action: 'postpone_custom',
      value: 'custom',
      label: t('OUTSIDER_CRM.TASKS.POSTPONE.CUSTOM'),
      icon: 'i-lucide-calendar',
    });
  }
  if (task.can_edit) {
    items.push({
      action: 'delete',
      value: 'delete',
      label: t('OUTSIDER_CRM.TASKS.DELETE'),
      icon: 'i-lucide-trash-2',
    });
  }
  return items;
};

const onMenu = (task, { action, value }) => {
  menuFor.value = null;
  if (action === 'delete') remove(task);
  else if (value === 'custom') {
    const date = postponeTo(task, 'tomorrow');
    postponeForm.value = { date: toDateInput(date), time: toTimeInput(date) };
    postponing.value = task.id;
  } else postpone(task, postponeTo(task, value));
};

const saveCustomPostpone = task => {
  const iso = combineDateTime(postponeForm.value.date, postponeForm.value.time);
  postponing.value = null;
  if (iso) postpone(task, new Date(iso));
};

const canCreate = computed(() => props.opportunity.can_edit);

watch(() => props.opportunity.id, load);
onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex items-center justify-between gap-2">
      <span v-if="!loadError" class="text-xs text-n-slate-11">
        {{
          pending.length
            ? t('OUTSIDER_CRM.TASKS.PENDING_COUNT', { count: pending.length })
            : t('OUTSIDER_CRM.TASKS.NONE_PENDING')
        }}
      </span>
      <span v-else />
      <Button
        v-if="canCreate && !showForm"
        type="button"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-plus"
        :label="t('OUTSIDER_CRM.TASKS.NEW')"
        @click="showForm = true"
      />
    </div>

    <TaskForm
      v-if="showForm"
      :opportunity="opportunity"
      @saved="onCreated"
      @cancel="showForm = false"
    />

    <div v-if="isLoading" class="flex justify-center p-4 text-n-slate-10">
      <Spinner :size="18" />
    </div>

    <LoadError v-else-if="loadError" :message="loadError" @retry="load" />

    <ul
      v-else-if="pending.length || (showDone && done.length)"
      class="flex flex-col mb-0 overflow-visible list-none divide-y rounded-lg divide-n-weak outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <li
        v-for="task in showDone ? [...pending, ...done] : pending"
        :key="task.id"
        class="flex items-start gap-2.5 px-3 py-2.5"
        :class="{ 'bg-n-ruby-2': task.overdue }"
      >
        <button
          type="button"
          class="flex items-center justify-center rounded-full outline outline-2 -outline-offset-2 size-6 shrink-0 disabled:cursor-default"
          :class="
            task.completed_at
              ? 'bg-n-teal-9 outline-n-teal-9 text-white'
              : 'outline-n-slate-8 enabled:hover:outline-n-teal-9 enabled:hover:bg-n-teal-3'
          "
          :disabled="!task.can_complete || busyId === task.id"
          :title="
            task.completed_at
              ? t('OUTSIDER_CRM.TASKS.REOPEN')
              : t('OUTSIDER_CRM.TASKS.COMPLETE')
          "
          :aria-label="
            task.completed_at
              ? t('OUTSIDER_CRM.TASKS.REOPEN')
              : t('OUTSIDER_CRM.TASKS.COMPLETE')
          "
          @click="toggle(task)"
        >
          <Icon v-if="task.completed_at" icon="i-lucide-check" class="size-3" />
        </button>
        <div class="flex flex-col flex-1 min-w-0 gap-0.5">
          <span
            class="flex items-center gap-1.5 text-sm"
            :class="
              task.completed_at
                ? 'line-through text-n-slate-10'
                : 'text-n-slate-12'
            "
          >
            <Icon
              :icon="taskKindIcon(task.kind)"
              class="size-3.5 shrink-0 text-n-slate-10"
              :title="t(`OUTSIDER_CRM.TASKS.KINDS.${task.kind.toUpperCase()}`)"
            />
            <span class="truncate">{{ task.title }}</span>
          </span>
          <span
            class="flex flex-wrap items-center text-xs gap-x-2 text-n-slate-11"
          >
            <span
              v-if="task.due_at && !task.completed_at"
              class="inline-flex items-center gap-1"
              :class="{ 'font-medium text-n-ruby-11': task.overdue }"
            >
              <Icon icon="i-lucide-clock" class="size-3" />
              {{ formatDateTime(task.due_at, t) }}
              <template v-if="task.overdue">
                · {{ t('OUTSIDER_CRM.TASKS.LATE') }}
              </template>
            </span>
            <span v-if="task.assignee" class="inline-flex items-center gap-1">
              <Icon icon="i-lucide-user" class="size-3" />
              {{ task.assignee.name }}
            </span>
            <span v-if="task.completed_at">
              {{
                t('OUTSIDER_CRM.TASKS.DONE_BY', {
                  name: task.completed_by?.name || '—',
                  date: formatDateTime(task.completed_at, t),
                })
              }}
            </span>
          </span>
          <p
            v-if="task.description"
            class="mb-0 text-xs whitespace-pre-wrap text-n-slate-11"
          >
            {{ task.description }}
          </p>
          <div
            v-if="postponing === task.id"
            class="flex flex-wrap items-center gap-2 mt-1"
          >
            <input
              v-model="postponeForm.date"
              type="date"
              class="!mb-0 h-7 px-2 text-xs rounded-md reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
            />
            <input
              v-model="postponeForm.time"
              type="time"
              class="!mb-0 h-7 px-2 text-xs rounded-md reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
            />
            <Button
              type="button"
              size="xs"
              :label="t('OUTSIDER_CRM.TASKS.POSTPONE.SAVE')"
              @click="saveCustomPostpone(task)"
            />
            <Button
              type="button"
              size="xs"
              variant="ghost"
              color="slate"
              :label="t('OUTSIDER_CRM.CANCEL')"
              @click="postponing = null"
            />
          </div>
        </div>
        <Spinner
          v-if="busyId === task.id"
          :size="14"
          class="mt-1 text-n-slate-10"
        />
        <div v-else-if="menuItems(task).length" class="relative shrink-0">
          <Button
            type="button"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-ellipsis-vertical"
            :title="t('OUTSIDER_CRM.TASKS.MORE')"
            @click.stop="menuFor = menuFor === task.id ? null : task.id"
          />
          <DropdownMenu
            v-if="menuFor === task.id"
            v-on-click-outside="() => (menuFor = null)"
            :menu-items="menuItems(task)"
            class="top-full mt-1 ltr:right-0 rtl:left-0 min-w-44"
            @action="onMenu(task, $event)"
          />
        </div>
      </li>
    </ul>

    <p
      v-else-if="!showForm"
      class="px-3 py-4 mb-0 text-sm text-center rounded-lg text-n-slate-11 bg-n-alpha-1"
    >
      {{
        canCreate
          ? t('OUTSIDER_CRM.TASKS.EMPTY')
          : t('OUTSIDER_CRM.TASKS.EMPTY_READ_ONLY')
      }}
    </p>

    <button
      v-if="done.length && !loadError"
      type="button"
      class="self-start text-xs text-n-slate-11 hover:text-n-slate-12 hover:underline"
      @click="showDone = !showDone"
    >
      {{
        showDone
          ? t('OUTSIDER_CRM.TASKS.HIDE_DONE')
          : t('OUTSIDER_CRM.TASKS.SHOW_DONE', { count: done.length })
      }}
    </button>
  </div>
</template>
