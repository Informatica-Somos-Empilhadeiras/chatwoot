<script setup>
// OUTSIDER: formulário curto de tarefa: o que fazer, tipo, prazo (data e hora) e responsável.
// Vendedor fica com as próprias tarefas; gestor e administrador escolhem quem faz.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { crmState, ensureCrmContext, loadUnitMembers } from '../crmStore';
import {
  TASK_KINDS,
  combineDateTime,
  errorMessage,
  toDateInput,
} from '../helpers';

const props = defineProps({
  opportunity: { type: Object, required: true },
});

const emit = defineEmits(['saved', 'cancel']);

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const tomorrow = () => {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  return toDateInput(date);
};

const isSaving = ref(false);
const members = ref([]);
const titleInput = ref(null);
const form = ref({
  title: '',
  kind: 'todo',
  date: tomorrow(),
  time: '09:00',
  assignee_id: currentUser.value.id,
  description: '',
});

const canAssign = computed(
  () =>
    crmState.access.administrator ||
    crmState.access.units.some(
      unit =>
        unit.id === props.opportunity.business_unit_id &&
        unit.role === 'manager'
    )
);

const kindOptions = computed(() =>
  TASK_KINDS.map(kind => ({
    value: kind.value,
    label: t(`OUTSIDER_CRM.TASKS.KINDS.${kind.value.toUpperCase()}`),
  }))
);

// membros da unidade e administradores da conta (os únicos que o backend aceita)
const assigneeOptions = computed(() => {
  const people = new Map();
  people.set(currentUser.value.id, currentUser.value.name);
  members.value.forEach(member => people.set(member.id, member.name));
  agents.value
    .filter(agent => agent.role === 'administrator')
    .forEach(agent => people.set(agent.id, agent.name));
  return [...people].map(([value, label]) => ({ value, label }));
});

const submit = async () => {
  if (!form.value.title.trim() || isSaving.value) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.createTask(props.opportunity.id, {
      title: form.value.title.trim(),
      kind: form.value.kind,
      due_at: combineDateTime(form.value.date, form.value.time),
      assignee_id: form.value.assignee_id,
      description: form.value.description.trim(),
    });
    emit('saved', data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

onMounted(async () => {
  titleInput.value?.focus();
  await ensureCrmContext();
  if (!canAssign.value) return;
  if (!agents.value.length) store.dispatch('agents/get');
  // quem gerencia a unidade começa com o responsável do negócio
  form.value.assignee_id =
    props.opportunity.owner?.id || form.value.assignee_id;
  try {
    members.value = await loadUnitMembers(props.opportunity.business_unit_id);
  } catch {
    members.value = [];
  }
});
</script>

<template>
  <form
    class="flex flex-col gap-3 p-3 rounded-lg bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak"
    @submit.prevent="submit"
  >
    <input
      ref="titleInput"
      v-model="form.title"
      type="text"
      maxlength="255"
      class="!mb-0 w-full px-3 py-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
      :placeholder="t('OUTSIDER_CRM.TASKS.TITLE_PLACEHOLDER')"
    />
    <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.TASKS.KIND') }}
        <Select
          v-model="form.kind"
          :options="kindOptions"
          class="!w-full [&>select]:w-full"
        />
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.TASKS.DUE_DATE') }}
        <input
          v-model="form.date"
          type="date"
          class="!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
        />
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.TASKS.DUE_TIME') }}
        <input
          v-model="form.time"
          type="time"
          class="!mb-0 h-8 px-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
        />
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.TASKS.ASSIGNEE') }}
        <Select
          v-model="form.assignee_id"
          :options="assigneeOptions"
          :disabled="!canAssign"
          class="!w-full [&>select]:w-full"
        />
      </label>
    </div>
    <textarea
      v-model="form.description"
      rows="2"
      maxlength="5000"
      class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
      :placeholder="t('OUTSIDER_CRM.TASKS.DESCRIPTION_PLACEHOLDER')"
    />
    <div class="flex justify-end gap-2">
      <Button
        type="button"
        size="sm"
        variant="faded"
        color="slate"
        :label="t('OUTSIDER_CRM.CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        type="submit"
        size="sm"
        :label="t('OUTSIDER_CRM.TASKS.ADD')"
        :is-loading="isSaving"
        :disabled="!form.title.trim()"
      />
    </div>
  </form>
</template>
