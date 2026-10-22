<script setup>
// OUTSIDER: selo da proposta mais recente do negócio (Entrega 18) no card do Kanban e na tabela:
// rascunho, enviada há quantos dias, aceita, recusada ou vencida, com o aviso âmbar "vence em N d"
// quando a validade da enviada acaba em até 2 dias. Só aparece a proposta que a pessoa pode ver;
// clicar abre a proposta.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { CRM_ROUTE } from '../sections';
import { daysUntil, formatMoney } from '../helpers';
import { PROPOSAL_STATUS_COLORS } from './proposals/proposalHelpers';

const props = defineProps({
  proposal: { type: Object, required: true },
});

const SOON_DAYS = 2;

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const prefix = 'OUTSIDER_CRM.BOARD.PROPOSAL';

const sentWhen = computed(() => {
  if (!props.proposal.sent_at) return null;
  const days = -daysUntil(props.proposal.sent_at.slice(0, 10));
  if (days <= 0) return t(`${prefix}.TODAY`);
  if (days === 1) return t(`${prefix}.YESTERDAY`);
  return t(`${prefix}.DAYS_AGO`, { days });
});

// enviada com a validade acabando: quantos dias faltam
const expiresIn = computed(() => {
  if (props.proposal.status !== 'sent' || !props.proposal.valid_until) {
    return null;
  }
  const days = daysUntil(props.proposal.valid_until);
  return days >= 0 && days <= SOON_DAYS ? days : null;
});

const label = computed(() => {
  const { status, number } = props.proposal;
  if (status === 'sent') {
    return sentWhen.value
      ? t(`${prefix}.SENT`, { when: sentWhen.value })
      : t(`${prefix}.SENT_NO_DATE`);
  }
  return t(`${prefix}.${status.toUpperCase()}`, { number });
});

const expiresText = computed(() => {
  if (expiresIn.value === null) return '';
  return expiresIn.value === 0
    ? t(`${prefix}.EXPIRES_TODAY`)
    : t(`${prefix}.EXPIRES_IN`, { days: expiresIn.value });
});

const tooltip = computed(() =>
  [
    t(`${prefix}.TOOLTIP`, {
      number: props.proposal.number,
      total: formatMoney(props.proposal.total_cents),
    }),
    props.proposal.count > 1 &&
      t(`${prefix}.MORE`, { count: props.proposal.count }),
  ]
    .filter(Boolean)
    .join(' · ')
);

const route = computed(() =>
  accountScopedRoute(
    CRM_ROUTE,
    { tab: 'proposals' },
    { proposta: props.proposal.id }
  )
);
</script>

<template>
  <span class="inline-flex flex-wrap items-center self-start max-w-full gap-1">
    <router-link
      v-tooltip.top="tooltip"
      :to="route"
      class="inline-flex items-center max-w-full gap-1 px-1.5 py-0.5 text-xs rounded-md hover:underline"
      :class="PROPOSAL_STATUS_COLORS[proposal.status]"
      data-proposal-badge
      @click.stop
      @mousedown.stop
    >
      <Icon icon="i-lucide-file-text" class="size-3 shrink-0" />
      <span class="truncate">{{ label }}</span>
    </router-link>
    <span
      v-if="expiresText"
      class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs font-medium rounded-md"
      :class="PROPOSAL_STATUS_COLORS.expired"
    >
      <Icon icon="i-lucide-calendar-clock" class="size-3 shrink-0" />
      {{ expiresText }}
    </span>
  </span>
</template>
