<script setup>
// OUTSIDER: abas Tarefas, Linha do tempo e Auditoria de um negócio. Usado na aba CRM da conversa
// e no painel do negócio na tela do CRM.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TaskList from './TaskList.vue';
import ActivityTimeline from './ActivityTimeline.vue';
import AuditList from './AuditList.vue';
import { bumpActivity } from '../crmStore';

const props = defineProps({
  opportunity: { type: Object, required: true },
  conversationDisplayId: { type: Number, default: null },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();

const active = ref('tasks');

const tabs = computed(() => [
  {
    key: 'tasks',
    icon: 'i-lucide-list-checks',
    label: t('OUTSIDER_CRM.ACTIVITY_TABS.TASKS'),
    count: props.opportunity.tasks?.pending || 0,
    alert: (props.opportunity.tasks?.overdue || 0) > 0,
  },
  {
    key: 'timeline',
    icon: 'i-lucide-history',
    label: t('OUTSIDER_CRM.ACTIVITY_TABS.TIMELINE'),
  },
  {
    key: 'audit',
    icon: 'i-lucide-shield-check',
    label: t('OUTSIDER_CRM.ACTIVITY_TABS.AUDIT'),
  },
]);

// tarefa criada ou concluída também entra na linha do tempo
const onTasksChanged = () => {
  bumpActivity(props.opportunity.id);
  emit('changed');
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex gap-1 border-b border-n-weak">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="flex items-center gap-1.5 px-3 py-2 -mb-px text-sm border-b-2"
        :class="
          active === tab.key
            ? 'border-n-brand text-n-slate-12 font-medium'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="active = tab.key"
      >
        <Icon :icon="tab.icon" class="size-3.5" />
        {{ tab.label }}
        <span
          v-if="tab.count"
          class="px-1.5 text-xs rounded-full"
          :class="
            tab.alert
              ? 'bg-n-ruby-9 text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          {{ tab.count }}
        </span>
      </button>
    </div>
    <TaskList
      v-if="active === 'tasks'"
      :opportunity="opportunity"
      @changed="onTasksChanged"
    />
    <ActivityTimeline
      v-else-if="active === 'timeline'"
      :opportunity="opportunity"
      :conversation-display-id="conversationDisplayId"
      @changed="emit('changed')"
    />
    <AuditList v-else :opportunity="opportunity" />
  </div>
</template>
