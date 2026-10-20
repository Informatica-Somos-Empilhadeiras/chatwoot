<script setup>
// OUTSIDER: "Histórico multiempresa" de um contato. No topo, as unidades do grupo com quem ele já
// negociou e o resultado em cada uma; no modo completo, o caminho de cada jornada em diagrama
// horizontal (JourneyFlow), com cada encaminhamento (quem, quando, motivo, observação e tentativa
// contra o limite). Os negócios de unidades que o usuário não acompanha aparecem só em resumo.
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JourneyFlow from './JourneyFlow.vue';
import { crmState, loadContactHistory } from '../crmStore';
import { STATUS_COLORS, formatMoneyShort } from '../helpers';

const props = defineProps({
  contactId: { type: Number, default: null },
  // negócio aberto na tela: a jornada dele vem primeiro, com destaque
  opportunityId: { type: Number, default: null },
  // só a lista de unidades (painel do contato)
  compact: { type: Boolean, default: false },
  // dentro de um cartão (aba CRM da conversa)
  boxed: { type: Boolean, default: false },
  // sem a jornada do negócio aberto (o painel do negócio já mostra o caminho dela no topo)
  skipCurrent: { type: Boolean, default: false },
});

const emit = defineEmits(['open']);

const { t } = useI18n();

const history = computed(() => crmState.histories[props.contactId]);
const journeys = computed(() => history.value?.journeys || []);
const allOpportunities = computed(() =>
  journeys.value.flatMap(journey => journey.opportunities)
);
// encaminhamento que saiu de cada negócio (no máximo um: o encaminhado não muda mais)
const forwardsByOrigin = computed(
  () =>
    new Map(
      journeys.value
        .flatMap(journey => journey.forwards)
        .map(forward => [forward.from_opportunity_id, forward])
    )
);

const forwardFrom = opportunityId => forwardsByOrigin.value.get(opportunityId);

const isOpen = item => item.status === 'open';

// uma linha por unidade: o negócio aberto dela ou, sem aberto, o mais recente
const units = computed(() => {
  const byUnit = new Map();
  allOpportunities.value.forEach(item => {
    const current = byUnit.get(item.business_unit.id);
    const better =
      !current ||
      (isOpen(item) && !isOpen(current)) ||
      (isOpen(item) === isOpen(current) && item.id > current.id);
    if (better) byUnit.set(item.business_unit.id, item);
  });
  return [...byUnit.values()].sort((a, b) =>
    a.business_unit.name.localeCompare(b.business_unit.name)
  );
});

const year = timestamp => (timestamp ? new Date(timestamp).getFullYear() : '');

const unitStatus = item => {
  switch (item.status) {
    case 'open':
      return t('OUTSIDER_CRM.HISTORY.UNIT_OPEN', {
        value: formatMoneyShort(item.value_cents),
      });
    case 'won':
      return t('OUTSIDER_CRM.HISTORY.UNIT_WON', { year: year(item.closed_at) });
    case 'lost':
      return t('OUTSIDER_CRM.HISTORY.UNIT_LOST', {
        year: year(item.closed_at),
      });
    default:
      return t('OUTSIDER_CRM.HISTORY.UNIT_FORWARDED', {
        unit: forwardFrom(item.id)?.to_unit || '—',
      });
  }
};

// jornadas que contam história (mais de uma unidade ou algum encaminhamento); a do negócio
// aberto na tela primeiro
const hasCurrent = journey =>
  journey.opportunities.some(item => item.id === props.opportunityId);

const storyJourneys = computed(() => {
  const list = journeys.value.filter(
    journey =>
      (journey.forwards.length ||
        journey.opportunities.length > 1 ||
        journey.upcoming?.length) &&
      !(props.skipCurrent && hasCurrent(journey))
  );
  return [...list].sort((a, b) => hasCurrent(b) - hasCurrent(a));
});

const visible = computed(() => {
  const manyUnits = units.value.length > 1 || forwardsByOrigin.value.size > 0;
  if (props.compact) return manyUnits;
  if (props.skipCurrent) return manyUnits || storyJourneys.value.length > 0;
  return storyJourneys.value.length > 0;
});

watch(
  () => props.contactId,
  () => {
    if (props.contactId && !history.value) {
      loadContactHistory(props.contactId).catch(() => {});
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="visible"
    class="flex flex-col gap-3"
    :class="{
      'p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container':
        boxed,
    }"
  >
    <div class="flex flex-col gap-0.5">
      <span
        class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
      >
        <Icon icon="i-lucide-building-2" class="size-4 text-n-slate-10" />
        {{ t('OUTSIDER_CRM.HISTORY.TITLE') }}
      </span>
      <span class="text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.HISTORY.SUBTITLE') }}
      </span>
    </div>

    <ul class="flex flex-col gap-1.5 mb-0 list-none">
      <li
        v-for="item in units"
        :key="item.business_unit.id"
        class="flex items-center justify-between gap-2 px-2.5 py-1.5 text-sm rounded-lg bg-n-alpha-1"
      >
        <span class="truncate text-n-slate-12">
          {{ item.business_unit.name }}
        </span>
        <span
          class="px-1.5 py-0.5 text-xs rounded-md shrink-0"
          :class="STATUS_COLORS[item.status]"
        >
          {{ unitStatus(item) }}
        </span>
      </li>
    </ul>

    <template v-if="!compact">
      <div
        v-for="journey in storyJourneys"
        :key="journey.id"
        class="p-3 rounded-lg bg-n-alpha-1"
      >
        <JourneyFlow
          :journey="journey"
          :max-attempts="history.max_forward_attempts"
          :opportunity-id="opportunityId"
          @open="item => emit('open', item)"
        />
      </div>
    </template>
  </div>
</template>
