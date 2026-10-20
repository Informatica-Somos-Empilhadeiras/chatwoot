<script setup>
// OUTSIDER: lista das regras "quando acontecer X, faça Y" da conta (ver RuleDialog.vue). Cada linha
// diz quando a regra roda, onde vale e o que faz; dá para ligar e desligar sem abrir a regra.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsSection from './SettingsSection.vue';
import RuleDialog from './RuleDialog.vue';
import { errorMessage, formatMoney } from '../../helpers';
import { ACTION_ICONS, splitHours } from './ruleForm';

const props = defineProps({
  units: { type: Array, required: true },
  pipelines: { type: Array, required: true },
});

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');

const rules = ref([]);
const isLoading = ref(true);
const dialogRef = ref(null);
const deleteRef = ref(null);
const deleting = ref(null);

const agentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);
const labelOptions = computed(() =>
  labels.value.map(label => ({ value: label.title, label: label.title }))
);

const load = async () => {
  try {
    const { data } = await CrmAPI.getAutomationRules();
    rules.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const duration = hours => {
  const { amount, unit } = splitHours(hours);
  return t(
    `OUTSIDER_CRM.SETTINGS.RULES.${unit === 'days' ? 'DAYS' : 'HOURS'}`,
    amount
  );
};

const whenText = rule => {
  const trigger = t(
    `OUTSIDER_CRM.SETTINGS.RULES.TRIGGERS.${rule.trigger.toUpperCase()}`
  );
  return rule.wait_hours
    ? t('OUTSIDER_CRM.SETTINGS.RULES.SUMMARY.WAIT', {
        trigger,
        time: duration(rule.wait_hours),
      })
    : trigger;
};

// onde a regra vale: unidade, pipeline, etapa e valor mínimo, só o que foi escolhido
const whereText = rule => {
  const conditions = rule.conditions || {};
  const pipeline = props.pipelines.find(p => p.id === conditions.pipeline_id);
  const parts = [
    props.units.find(unit => unit.id === conditions.business_unit_id)?.name,
    pipeline?.name,
    pipeline?.stages.find(stage => stage.id === conditions.stage_id)?.name,
    conditions.min_value_cents !== null &&
      conditions.min_value_cents !== undefined &&
      t('OUTSIDER_CRM.SETTINGS.RULES.SUMMARY.MIN_VALUE', {
        value: formatMoney(conditions.min_value_cents),
      }),
  ].filter(Boolean);
  return parts.length
    ? parts.join(' · ')
    : t('OUTSIDER_CRM.SETTINGS.RULES.SUMMARY.EVERYWHERE');
};

const personName = id =>
  agents.value.find(agent => agent.id === id)?.name || '—';

const actionText = action => {
  switch (action.type) {
    case 'create_task':
      return action.assignee === 'managers'
        ? t('OUTSIDER_CRM.SETTINGS.RULES.SUMMARY.TASK_MANAGERS', {
            title: action.title,
          })
        : action.title;
    case 'set_owner':
      return t('OUTSIDER_CRM.SETTINGS.RULES.SUMMARY.OWNER', {
        name: personName(action.user_id),
      });
    case 'add_label':
      return action.label;
    default:
      return t('OUTSIDER_CRM.SETTINGS.RULES.ACTIONS.ADD_NOTE');
  }
};

const toggle = async rule => {
  try {
    await CrmAPI.updateAutomationRule(rule.id, { active: !rule.active });
    await load();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const askDelete = rule => {
  deleting.value = rule;
  deleteRef.value?.open();
};

const confirmDelete = async () => {
  try {
    await CrmAPI.deleteAutomationRule(deleting.value.id);
    deleteRef.value?.close();
    await load();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('labels/get');
  load();
});
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.RULES.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.RULES.DESCRIPTION')"
  >
    <template #actions>
      <Button
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.SETTINGS.RULES.NEW')"
        @click="dialogRef?.open()"
      />
    </template>

    <div
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <p
        v-if="!isLoading && !rules.length"
        class="p-6 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.SETTINGS.RULES.EMPTY') }}
      </p>
      <div
        v-for="rule in rules"
        :key="rule.id"
        class="flex flex-wrap items-start justify-between gap-3 px-4 py-3 border-b border-n-weak last:border-0"
      >
        <div class="flex flex-col flex-1 min-w-[14rem] gap-1.5">
          <span
            class="text-sm font-medium"
            :class="rule.active ? 'text-n-slate-12' : 'text-n-slate-10'"
          >
            {{ rule.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              t('OUTSIDER_CRM.SETTINGS.RULES.SUMMARY.WHEN', {
                when: whenText(rule),
              })
            }}
            · {{ whereText(rule) }}
          </span>
          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="(action, index) in rule.actions"
              :key="index"
              class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
            >
              <Icon
                :icon="ACTION_ICONS[action.type]"
                class="size-3 text-n-slate-11"
              />
              {{ actionText(action) }}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-1">
          <Switch
            v-tooltip.top="t('OUTSIDER_CRM.SETTINGS.ACTIVE')"
            :model-value="rule.active"
            @change="toggle(rule)"
          />
          <Button
            v-tooltip.top="t('OUTSIDER_CRM.SETTINGS.RULES.EDIT')"
            icon="i-lucide-pencil"
            size="sm"
            variant="ghost"
            color="slate"
            @click="dialogRef?.open(rule)"
          />
          <Button
            v-tooltip.top="t('OUTSIDER_CRM.SETTINGS.RULES.DELETE')"
            icon="i-lucide-trash-2"
            size="sm"
            variant="ghost"
            color="ruby"
            @click="askDelete(rule)"
          />
        </div>
      </div>
    </div>

    <RuleDialog
      ref="dialogRef"
      :units="units"
      :pipelines="pipelines"
      :agent-options="agentOptions"
      :label-options="labelOptions"
      @saved="load"
    />
    <Dialog
      ref="deleteRef"
      type="alert"
      :title="t('OUTSIDER_CRM.SETTINGS.RULES.DELETE_TITLE')"
      :description="
        t('OUTSIDER_CRM.SETTINGS.RULES.DELETE_DESCRIPTION', {
          name: deleting?.name,
        })
      "
      :confirm-button-label="t('OUTSIDER_CRM.SETTINGS.RULES.DELETE')"
      @confirm="confirmDelete"
    />
  </SettingsSection>
</template>
