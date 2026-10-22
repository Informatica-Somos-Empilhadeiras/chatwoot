<script setup>
// OUTSIDER: card de um negócio no Kanban. Tarefa atrasada deixa o card com borda vermelha;
// negócio recebido por encaminhamento mostra de qual unidade veio. Com o destaque ligado nas
// automações, negócio aberto sem tarefa pendente mostra "Sem próxima tarefa". Recebido por
// encaminhamento e ainda não aberto pelo usuário mostra "Novo" em vermelho. Sem responsável, quem é
// da unidade vê o botão "Pegar" (fica com o negócio). Com proposta, o selo dela (Entrega 18).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate, formatDateTime, formatMoney } from '../helpers';
import { isReceived } from '../crmStore';
import ProposalBadge from './ProposalBadge.vue';

const props = defineProps({
  opportunity: { type: Object, required: true },
  noNextTask: { type: Boolean, default: false },
  isClaiming: { type: Boolean, default: false },
});

const emit = defineEmits(['claim']);

const { t } = useI18n();

const isNew = computed(() => isReceived(props.opportunity.id));
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
        <span
          v-if="isNew"
          class="inline-flex items-center px-1.5 me-1 text-[11px] font-semibold rounded-md bg-n-ruby-9 text-white align-[1px]"
        >
          {{ t('OUTSIDER_CRM.NOTICE.NEW') }}
        </span>
        {{ opportunity.title }}
      </span>
      <Icon
        v-if="!opportunity.can_edit && !opportunity.can_claim"
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

    <span
      v-if="opportunity.forwarded_from"
      class="inline-flex items-center self-start gap-1 px-1.5 py-0.5 text-xs rounded-md bg-n-amber-3 text-n-amber-11"
      :title="opportunity.forwarded_from.code"
    >
      <Icon icon="i-lucide-inbox" class="size-3" />
      {{
        t('OUTSIDER_CRM.FORWARD.FROM_UNIT', {
          unit: opportunity.forwarded_from.business_unit_name,
        })
      }}
    </span>

    <ProposalBadge
      v-if="opportunity.proposal"
      :proposal="opportunity.proposal"
    />

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
        :title="
          t('OUTSIDER_CRM.BOARD.TASKS_PENDING', {
            count: opportunity.tasks.pending,
          })
        "
      >
        <Icon icon="i-lucide-list-checks" class="size-3" />
        {{
          opportunity.tasks.next_due_at
            ? formatDateTime(opportunity.tasks.next_due_at, t)
            : opportunity.tasks.pending
        }}
      </span>
      <span
        v-if="noNextTask"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-n-amber-3 text-n-amber-11"
      >
        <Icon icon="i-lucide-calendar-x" class="size-3" />
        {{ t('OUTSIDER_CRM.BOARD.NO_NEXT_TASK') }}
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

    <div
      v-if="!opportunity.owner && opportunity.status === 'open'"
      class="flex items-center justify-between gap-2 pt-2 border-t border-n-weak"
    >
      <span class="text-xs text-n-amber-11">
        {{ t('OUTSIDER_CRM.CLAIM.NO_OWNER') }}
      </span>
      <Button
        v-if="opportunity.can_claim"
        type="button"
        size="xs"
        icon="i-lucide-hand"
        :label="t('OUTSIDER_CRM.CLAIM.BUTTON')"
        :is-loading="isClaiming"
        @click.stop="emit('claim', opportunity)"
      />
    </div>
  </div>
</template>
