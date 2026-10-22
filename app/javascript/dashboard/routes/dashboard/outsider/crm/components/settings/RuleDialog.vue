<script setup>
// OUTSIDER: criar e editar uma regra "quando acontecer X, faça Y" (ver ruleForm.js e
// app/services/outsider/crm/automation_rules.rb). Na criação, modelos prontos preenchem o formulário.
// "Encaminhar para outra unidade" só aparece em "quando perder".
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { TASK_KINDS, errorMessage } from '../../helpers';
import { crmState, loadUnitMembers } from '../../crmStore';
import {
  ACTION_ICONS,
  ASSIGNEES,
  COUNTDOWN_TRIGGERS,
  LOST_TRIGGER,
  MAX_RULE_ACTIONS,
  RULE_ACTIONS,
  RULE_TRIGGERS,
  TIMED_TRIGGERS,
  blankAction,
  blankForm,
  formToRule,
  isFormValid,
  isProposalTrigger,
  ruleErrorMessage,
  ruleToForm,
} from './ruleForm';

const props = defineProps({
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
  agentOptions: { type: Array, required: true },
  labelOptions: { type: Array, required: true },
  lostReasons: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();
const agents = useMapGetter('agents/getAgents');

const dialogRef = ref(null);
const isSaving = ref(false);
const ruleId = ref(null);
const form = ref(blankForm());
// membros de cada unidade de destino, para escolher o responsável do encaminhamento
const members = ref({});

const isTimed = computed(() => TIMED_TRIGGERS.includes(form.value.trigger));
const isCountdown = computed(() =>
  COUNTDOWN_TRIGGERS.includes(form.value.trigger)
);
const isProposal = computed(() => isProposalTrigger(form.value.trigger));
// a mensagem mostra {proposta} ao pé da letra: o vue-i18n trocaria o que está entre chaves
const proposalHint = computed(() =>
  t('OUTSIDER_CRM.SETTINGS.RULES.PROPOSAL_PLACEHOLDER', {
    proposta: '{proposta}',
  })
);
const isLost = computed(() => form.value.trigger === LOST_TRIGGER);
const isValid = computed(() => isFormValid(form.value));

const options = (keys, path) =>
  keys.map(key => ({
    value: key,
    label: t(`OUTSIDER_CRM.SETTINGS.RULES.${path}.${key.toUpperCase()}`),
  }));

const triggerOptions = computed(() => options(RULE_TRIGGERS, 'TRIGGERS'));
const actionOptions = computed(() =>
  options(
    RULE_ACTIONS.filter(type => type !== 'forward' || isLost.value),
    'ACTIONS'
  )
);
const reasonOptions = (kinds, emptyKey) => [
  { value: '', label: t(`OUTSIDER_CRM.SETTINGS.RULES.${emptyKey}`) },
  ...props.lostReasons
    .filter(reason => reason.active !== false && kinds.includes(reason.kind))
    .map(reason => ({ value: reason.id, label: reason.name })),
];
const lostReasonOptions = computed(() =>
  reasonOptions(['lost', 'both'], 'ANY_LOST_REASON')
);
const forwardReasonOptions = computed(() =>
  reasonOptions(['forward', 'both'], 'FORWARD.USE_LOST_REASON')
);
const forwardUnitOptions = computed(() =>
  props.units
    .filter(unit => unit.active !== false)
    .map(unit => ({ value: unit.id, label: unit.name }))
);
const forwardPipelineOptions = action => [
  { value: '', label: t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.FIRST_PIPELINE') },
  ...props.pipelines
    .filter(
      pipeline =>
        pipeline.business_unit_id === action.to_business_unit_id &&
        pipeline.active !== false
    )
    .map(pipeline => ({ value: pipeline.id, label: pipeline.name })),
];
// Agente com o CRM desligado (Configurações > Acesso) sai das listas; se a regra já o usa, ele continua
// na lista com o aviso, para quem edita a regra saber que precisa trocar
const crmOff = id =>
  (crmState.access.disabled_user_ids || []).includes(Number(id));
const personLabel = (id, name) =>
  crmOff(id) ? t('OUTSIDER_CRM.SETTINGS.RULES.CRM_OFF', { name }) : name;
const personOptions = selectedId =>
  props.agentOptions
    .filter(
      option =>
        !crmOff(option.value) || Number(option.value) === Number(selectedId)
    )
    .map(option => ({
      ...option,
      label: personLabel(option.value, option.label),
    }));

// responsável no destino: membros da unidade e administradores da conta (mesma regra da API)
const ownerOptions = action => {
  const unitMembers = members.value[action.to_business_unit_id] || [];
  const ids = new Set(unitMembers.map(member => member.id));
  const admins = agents.value.filter(
    agent => agent.role === 'administrator' && !ids.has(agent.id)
  );
  return [
    { value: '', label: t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.NO_OWNER') },
    ...[...unitMembers, ...admins]
      .filter(
        person => !crmOff(person.id) || person.id === Number(action.owner_id)
      )
      .map(person => ({
        value: person.id,
        label: personLabel(person.id, person.name),
      })),
  ];
};

const loadMembers = async unitId => {
  if (!unitId || members.value[unitId]) return;
  try {
    members.value = {
      ...members.value,
      [unitId]: await loadUnitMembers(unitId),
    };
  } catch {
    // sem a lista, o encaminhamento ainda pode ir sem responsável
  }
};

const changeForwardUnit = (action, unitId) => {
  action.to_business_unit_id = unitId;
  action.pipeline_id = '';
  action.owner_id = '';
  loadMembers(unitId);
};
const assigneeOptions = computed(() => options(ASSIGNEES, 'ASSIGNEES'));
const unitOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.SETTINGS.RULES.ANY_UNIT') },
  ...props.units.map(unit => ({ value: unit.id, label: unit.name })),
]);
const pipelineOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.SETTINGS.RULES.ANY_PIPELINE') },
  ...props.pipelines
    .filter(
      pipeline =>
        !form.value.business_unit_id ||
        pipeline.business_unit_id === form.value.business_unit_id
    )
    .map(pipeline => ({ value: pipeline.id, label: pipeline.name })),
]);
const stageOptions = computed(() => {
  const pipeline = props.pipelines.find(p => p.id === form.value.pipeline_id);
  return [
    { value: '', label: t('OUTSIDER_CRM.SETTINGS.RULES.ANY_STAGE') },
    ...(pipeline?.stages || [])
      .filter(stage => stage.kind === 'open')
      .map(stage => ({ value: stage.id, label: stage.name })),
  ];
});
const kindOptions = computed(() =>
  TASK_KINDS.map(kind => ({
    value: kind.value,
    label: t(`OUTSIDER_CRM.TASKS.KINDS.${kind.value.toUpperCase()}`),
  }))
);
const unitTimeOptions = computed(() => [
  { value: 'hours', label: t('OUTSIDER_CRM.SETTINGS.RULES.HOURS_UNIT') },
  { value: 'days', label: t('OUTSIDER_CRM.SETTINGS.RULES.DAYS_UNIT') },
]);

// unidade e pipeline mudam o que vem abaixo: limpa o que deixou de fazer sentido
const changeUnit = value => {
  form.value.business_unit_id = value;
  if (!pipelineOptions.value.some(p => p.value === form.value.pipeline_id)) {
    form.value.pipeline_id = '';
    form.value.stage_id = '';
  }
};

const changePipeline = value => {
  form.value.pipeline_id = value;
  form.value.stage_id = '';
  const pipeline = props.pipelines.find(p => p.id === value);
  if (pipeline) form.value.business_unit_id = pipeline.business_unit_id;
};

const task = (titleKey, kind, hours, assignee = 'owner') => ({
  ...blankAction('create_task'),
  // {proposta} fica no título: a regra troca pelo número da proposta na hora de rodar
  title: t(`OUTSIDER_CRM.SETTINGS.RULES.PRESETS.${titleKey}`, {
    proposta: '{proposta}',
  }),
  kind,
  due_amount: hours % 24 === 0 && hours ? hours / 24 : hours,
  due_unit: hours % 24 === 0 && hours ? 'days' : 'hours',
  assignee,
});

const PRESETS = [
  {
    key: 'STAGE_TASKS',
    icon: 'i-lucide-list-todo',
    build: () => ({
      trigger: 'stage_entered',
      actions: [
        task('STAGE_TASK_1', 'proposal', 4),
        task('STAGE_TASK_2', 'call', 48),
      ],
    }),
  },
  {
    key: 'NEW_DEAL',
    icon: 'i-lucide-sparkles',
    build: () => ({
      trigger: 'created',
      actions: [task('NEW_DEAL_TASK', 'call', 2)],
    }),
  },
  {
    key: 'STALLED_MANAGERS',
    icon: 'i-lucide-hourglass',
    build: () => ({
      trigger: 'stalled',
      wait_amount: 5,
      wait_unit: 'days',
      actions: [task('STALLED_MANAGERS_TASK', 'follow_up', 0, 'managers')],
    }),
  },
  {
    key: 'LOST_FORWARD',
    icon: 'i-lucide-forward',
    build: () => ({
      trigger: 'lost',
      actions: [{ ...blankAction('forward') }],
    }),
  },
  {
    key: 'NEXT_TASK',
    icon: 'i-lucide-calendar-x',
    build: () => ({
      trigger: 'no_next_task',
      wait_amount: 1,
      wait_unit: 'days',
      actions: [task('NEXT_TASK_TASK', 'todo', 4)],
    }),
  },
  {
    key: 'PROPOSAL_NO_REPLY',
    icon: 'i-lucide-file-clock',
    build: () => ({
      trigger: 'proposal_no_reply',
      wait_amount: 3,
      wait_unit: 'days',
      actions: [task('PROPOSAL_NO_REPLY_TASK', 'call', 4)],
    }),
  },
  {
    key: 'PROPOSAL_EXPIRING',
    icon: 'i-lucide-calendar-clock',
    build: () => ({
      trigger: 'proposal_expiring',
      wait_amount: 2,
      wait_unit: 'days',
      actions: [task('PROPOSAL_EXPIRING_TASK', 'follow_up', 4)],
    }),
  },
  {
    key: 'PROPOSAL_REJECTED',
    icon: 'i-lucide-file-x',
    build: () => ({
      trigger: 'proposal_rejected',
      actions: [task('PROPOSAL_REJECTED_TASK', 'call', 24)],
    }),
  },
];

const applyPreset = preset => {
  form.value = {
    ...blankForm(),
    business_unit_id: form.value.business_unit_id,
    pipeline_id: form.value.pipeline_id,
    name: t(`OUTSIDER_CRM.SETTINGS.RULES.PRESETS.${preset.key}`),
    ...preset.build(),
  };
};

const open = (rule = null) => {
  ruleId.value = rule?.id ?? null;
  form.value = rule ? ruleToForm(rule) : blankForm();
  form.value.actions
    .filter(action => action.type === 'forward')
    .forEach(action => loadMembers(action.to_business_unit_id));
  dialogRef.value?.open();
};

const addAction = () => {
  if (form.value.actions.length < MAX_RULE_ACTIONS) {
    form.value.actions.push(blankAction());
  }
};

const changeActionType = (index, type) => {
  form.value.actions[index] = blankAction(type);
};

const save = async () => {
  if (!isValid.value) return;
  isSaving.value = true;
  try {
    const payload = formToRule(form.value);
    if (ruleId.value) {
      await CrmAPI.updateAutomationRule(ruleId.value, payload);
    } else {
      await CrmAPI.createAutomationRule(payload);
    }
    dialogRef.value?.close();
    emit('saved');
  } catch (error) {
    const fields = error?.response?.data?.fields;
    useAlert(
      Array.isArray(fields) && fields.length
        ? fields.map(field => ruleErrorMessage(t, field)).join(' ')
        : errorMessage(t, error)
    );
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      ruleId
        ? t('OUTSIDER_CRM.SETTINGS.RULES.EDIT')
        : t('OUTSIDER_CRM.SETTINGS.RULES.NEW')
    "
    width="2xl"
    overflow-y-auto
    :confirm-button-label="t('OUTSIDER_CRM.SAVE')"
    :is-loading="isSaving"
    :disable-confirm-button="!isValid"
    @confirm="save"
  >
    <div class="flex flex-col gap-5">
      <div v-if="!ruleId" class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.SETTINGS.RULES.PRESETS.TITLE') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="preset in PRESETS"
            :key="preset.key"
            type="button"
            class="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2 outline outline-1 -outline-offset-1 outline-n-weak"
            @click="applyPreset(preset)"
          >
            <Icon :icon="preset.icon" class="size-3.5 text-n-slate-11" />
            {{ t(`OUTSIDER_CRM.SETTINGS.RULES.PRESETS.${preset.key}`) }}
          </button>
        </div>
      </div>

      <div class="flex flex-wrap items-end gap-4">
        <Input
          v-model="form.name"
          class="flex-1 min-w-[14rem]"
          maxlength="80"
          :label="t('OUTSIDER_CRM.SETTINGS.RULES.NAME')"
          :placeholder="t('OUTSIDER_CRM.SETTINGS.RULES.NAME_PLACEHOLDER')"
        />
        <label class="flex items-center gap-2 pb-2 text-sm text-n-slate-12">
          <Switch v-model="form.active" />
          {{ t('OUTSIDER_CRM.SETTINGS.ACTIVE') }}
        </label>
      </div>

      <section class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.SETTINGS.RULES.WHEN') }}
        </span>
        <div class="flex flex-wrap items-end gap-3">
          <Select v-model="form.trigger" :options="triggerOptions" />
          <template v-if="isTimed">
            <span class="pb-2 text-sm text-n-slate-11">
              {{
                isCountdown
                  ? t(
                      'OUTSIDER_CRM.SETTINGS.RULES.WAIT_LABELS.PROPOSAL_EXPIRING'
                    )
                  : t('OUTSIDER_CRM.SETTINGS.RULES.FOR_MORE_THAN')
              }}
            </span>
            <Input
              v-model="form.wait_amount"
              type="number"
              min="1"
              class="w-20"
            />
            <Select v-model="form.wait_unit" :options="unitTimeOptions" />
          </template>
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{
            t(
              `OUTSIDER_CRM.SETTINGS.RULES.TRIGGER_HELP.${form.trigger.toUpperCase()}`
            )
          }}
        </p>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.OPPORTUNITY.UNIT') }}
            <Select
              :model-value="form.business_unit_id"
              :options="unitOptions"
              class="!w-full [&>select]:w-full"
              @update:model-value="changeUnit"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.RULES.PIPELINE') }}
            <Select
              :model-value="form.pipeline_id"
              :options="pipelineOptions"
              class="!w-full [&>select]:w-full"
              @update:model-value="changePipeline"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.RULES.STAGE') }}
            <Select
              v-model="form.stage_id"
              :options="stageOptions"
              :disabled="!form.pipeline_id"
              class="!w-full [&>select]:w-full"
            />
          </label>
          <label
            v-if="isLost"
            class="flex flex-col gap-1 text-xs text-n-slate-11"
          >
            {{ t('OUTSIDER_CRM.SETTINGS.RULES.LOST_REASON') }}
            <Select
              v-model="form.lost_reason_id"
              :options="lostReasonOptions"
              class="!w-full [&>select]:w-full"
            />
          </label>
          <label class="flex flex-col gap-1 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.SETTINGS.RULES.MIN_VALUE') }}
            <Input
              v-model="form.min_value"
              inputmode="decimal"
              :placeholder="
                t('OUTSIDER_CRM.SETTINGS.RULES.MIN_VALUE_PLACEHOLDER')
              "
            />
          </label>
        </div>
      </section>

      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.SETTINGS.RULES.DO') }}
          </span>
          <Button
            type="button"
            icon="i-lucide-plus"
            size="xs"
            variant="ghost"
            :label="t('OUTSIDER_CRM.SETTINGS.RULES.ADD_ACTION')"
            :disabled="form.actions.length >= MAX_RULE_ACTIONS"
            @click="addAction"
          />
        </div>
        <div
          v-for="(action, index) in form.actions"
          :key="index"
          class="flex flex-col gap-3 p-3 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <div class="flex items-center gap-2">
            <Icon
              :icon="ACTION_ICONS[action.type]"
              class="size-4 text-n-slate-11 shrink-0"
            />
            <Select
              :model-value="action.type"
              :options="actionOptions"
              @update:model-value="type => changeActionType(index, type)"
            />
            <div class="flex-1" />
            <Button
              type="button"
              icon="i-lucide-trash-2"
              size="xs"
              variant="ghost"
              color="ruby"
              :disabled="form.actions.length === 1"
              @click="form.actions.splice(index, 1)"
            />
          </div>

          <template v-if="action.type === 'create_task'">
            <div class="flex flex-wrap items-end gap-3">
              <Input
                v-model="action.title"
                class="flex-1 min-w-[14rem]"
                maxlength="255"
                :label="t('OUTSIDER_CRM.SETTINGS.RULES.TASK_TITLE')"
              />
              <Select v-model="action.kind" :options="kindOptions" />
            </div>
            <div class="flex flex-wrap items-end gap-3">
              <span class="pb-2 text-sm text-n-slate-11">
                {{ t('OUTSIDER_CRM.SETTINGS.RULES.DUE_IN') }}
              </span>
              <Input
                v-model="action.due_amount"
                type="number"
                min="0"
                class="w-20"
              />
              <Select v-model="action.due_unit" :options="unitTimeOptions" />
              <span class="pb-2 text-sm text-n-slate-11">
                {{ t('OUTSIDER_CRM.SETTINGS.RULES.FOR') }}
              </span>
              <Select v-model="action.assignee" :options="assigneeOptions" />
              <Select
                v-if="action.assignee === 'user'"
                v-model="action.user_id"
                :options="personOptions(action.user_id)"
                :placeholder="t('OUTSIDER_CRM.SETTINGS.RULES.CHOOSE_PERSON')"
              />
            </div>
            <textarea
              v-model="action.description"
              rows="2"
              maxlength="1000"
              class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
              :placeholder="t('OUTSIDER_CRM.SETTINGS.RULES.TASK_DESCRIPTION')"
            />
          </template>

          <template v-else-if="action.type === 'set_owner'">
            <Select
              v-model="action.user_id"
              :options="personOptions(action.user_id)"
              :placeholder="t('OUTSIDER_CRM.SETTINGS.RULES.CHOOSE_PERSON')"
            />
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.SETTINGS.RULES.SET_OWNER_HELP') }}
            </p>
          </template>

          <template v-else-if="action.type === 'add_label'">
            <Select
              v-model="action.label"
              :options="labelOptions"
              :placeholder="t('OUTSIDER_CRM.SETTINGS.RULES.CHOOSE_LABEL')"
            />
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.SETTINGS.RULES.LABEL_HELP') }}
            </p>
          </template>

          <template v-else-if="action.type === 'forward'">
            <p v-if="!isLost" class="mb-0 text-xs text-n-ruby-11">
              {{ t('OUTSIDER_CRM.SETTINGS.RULES.ERRORS.FORWARD_TRIGGER') }}
            </p>
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <label class="flex flex-col gap-1 text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.UNIT') }}
                <Select
                  :model-value="action.to_business_unit_id"
                  :options="forwardUnitOptions"
                  :placeholder="
                    t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.CHOOSE_UNIT')
                  "
                  class="!w-full [&>select]:w-full"
                  @update:model-value="
                    unitId => changeForwardUnit(action, unitId)
                  "
                />
              </label>
              <label class="flex flex-col gap-1 text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.SETTINGS.RULES.PIPELINE') }}
                <Select
                  v-model="action.pipeline_id"
                  :options="forwardPipelineOptions(action)"
                  :disabled="!action.to_business_unit_id"
                  class="!w-full [&>select]:w-full"
                />
              </label>
              <label class="flex flex-col gap-1 text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.OWNER') }}
                <Select
                  v-model="action.owner_id"
                  :options="ownerOptions(action)"
                  :disabled="!action.to_business_unit_id"
                  class="!w-full [&>select]:w-full"
                />
              </label>
              <label class="flex flex-col gap-1 text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.REASON') }}
                <Select
                  v-model="action.reason_id"
                  :options="forwardReasonOptions"
                  class="!w-full [&>select]:w-full"
                />
              </label>
            </div>
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <Switch v-model="action.create_task" />
              {{ t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.CREATE_TASK') }}
            </label>
            <textarea
              v-model="action.notes"
              rows="2"
              maxlength="2000"
              class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
              :placeholder="t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.NOTES')"
            />
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('OUTSIDER_CRM.SETTINGS.RULES.FORWARD.HELP') }}
            </p>
          </template>

          <textarea
            v-else
            v-model="action.body"
            rows="3"
            maxlength="2000"
            class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
            :placeholder="t('OUTSIDER_CRM.SETTINGS.RULES.NOTE_PLACEHOLDER')"
          />
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.SETTINGS.RULES.ACTIONS_HELP') }}
        </p>
        <p
          v-if="isProposal"
          class="flex items-start gap-1.5 mb-0 text-xs text-n-blue-11"
        >
          <Icon icon="i-lucide-file-text" class="size-3.5 mt-px shrink-0" />
          {{ proposalHint }}
        </p>
      </section>
    </div>
  </Dialog>
</template>
