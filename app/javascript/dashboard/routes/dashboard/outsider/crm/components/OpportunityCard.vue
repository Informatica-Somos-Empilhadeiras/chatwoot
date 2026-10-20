<script setup>
// OUTSIDER: card de um negócio no Kanban. Tarefa atrasada deixa o card com borda vermelha.
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate, formatDateTime, formatMoney } from '../helpers';

defineProps({
  opportunity: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col gap-2 p-3 text-sm border rounded-lg shadow-sm bg-n-solid-1"
    :class="[
      opportunity.can_edit ? 'cursor-grab' : 'cursor-pointer',
      opportunity.tasks?.overdue
        ? 'border-n-ruby-8 hover:border-n-ruby-9'
        : 'border-n-weak hover:border-n-slate-7',
    ]"
  >
    <div class="flex items-start justify-between gap-2">
      <span class="font-medium leading-snug text-n-slate-12 line-clamp-2">
        {{ opportunity.title }}
      </span>
      <Icon
        v-if="!opportunity.can_edit"
        v-tooltip="t('OUTSIDER_CRM.BOARD.READ_ONLY')"
        icon="i-lucide-lock"
        class="size-3.5 shrink-0 text-n-slate-9 mt-0.5"
      />
    </div>

    <div class="flex items-center min-w-0 gap-1.5 text-n-slate-11">
      <Avatar
        :name="opportunity.contact.name"
        :src="opportunity.contact.thumbnail"
        :size="18"
        rounded-full
      />
      <span class="truncate">{{ opportunity.contact.name }}</span>
    </div>

    <div class="flex items-center justify-between gap-2">
      <span class="font-semibold text-n-slate-12">
        {{ formatMoney(opportunity.value_cents) }}
      </span>
      <span class="text-xs text-n-slate-10">
        {{ opportunity.effective_probability }}%
      </span>
    </div>

    <div class="flex flex-wrap items-center gap-1.5 text-xs">
      <span
        v-if="opportunity.expected_close_on"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md"
        :class="
          opportunity.overdue
            ? 'bg-n-ruby-3 text-n-ruby-11'
            : 'bg-n-alpha-2 text-n-slate-11'
        "
        :title="
          opportunity.overdue ? t('OUTSIDER_CRM.BOARD.OVERDUE') : undefined
        "
      >
        <Icon icon="i-lucide-calendar" class="size-3" />
        {{ formatDate(opportunity.expected_close_on) }}
      </span>
      <span
        v-if="opportunity.tasks?.overdue"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-n-ruby-3 text-n-ruby-11"
      >
        <Icon icon="i-lucide-list-checks" class="size-3" />
        {{
          t('OUTSIDER_CRM.BOARD.TASKS_LATE', {
            count: opportunity.tasks.overdue,
          })
        }}
      </span>
      <span
        v-else-if="opportunity.tasks?.pending"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11"
        :title="t('OUTSIDER_CRM.BOARD.TASKS_PENDING', { count: opportunity.tasks.pending })"
      >
        <Icon icon="i-lucide-list-checks" class="size-3" />
        {{
          opportunity.tasks.next_due_at
            ? formatDateTime(opportunity.tasks.next_due_at, t)
            : opportunity.tasks.pending
        }}
      </span>
      <span
        v-if="opportunity.sla_exceeded"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-n-amber-3 text-n-amber-11"
      >
        <Icon icon="i-lucide-clock-alert" class="size-3" />
        {{ t('OUTSIDER_CRM.BOARD.SLA') }}
      </span>
      <div class="flex-1" />
      <span class="text-n-slate-10">{{ opportunity.code }}</span>
      <Avatar
        v-if="opportunity.owner"
        v-tooltip="opportunity.owner.name"
        :name="opportunity.owner.name"
        :src="opportunity.owner.thumbnail"
        :size="18"
        rounded-full
      />
    </div>
  </div>
</template>
