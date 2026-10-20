<script setup>
// OUTSIDER: "Histórico multiempresa" de um contato. No topo, as unidades do grupo com quem ele já
// negociou e o resultado em cada uma; no modo completo, a jornada passo a passo, com cada
// encaminhamento (quem, quando, motivo, observação e tentativa contra o limite).
// Os negócios de unidades que o usuário não acompanha aparecem só em resumo.
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { crmState, loadContactHistory } from '../crmStore';
import {
  STATUS_COLORS,
  formatDate,
  formatDateTime,
  formatMoney,
  formatMoneyShort,
} from '../helpers';

const props = defineProps({
  contactId: { type: Number, default: null },
  // negócio aberto na tela: a jornada dele vem primeiro, com destaque
  opportunityId: { type: Number, default: null },
  // só a lista de unidades (painel do contato)
  compact: { type: Boolean, default: false },
  // dentro de um cartão (aba CRM da conversa)
  boxed: { type: Boolean, default: false },
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
const storyJourneys = computed(() => {
  const list = journeys.value.filter(
    journey => journey.forwards.length || journey.opportunities.length > 1
  );
  return [...list].sort(
    (a, b) =>
      b.opportunities.some(item => item.id === props.opportunityId) -
      a.opportunities.some(item => item.id === props.opportunityId)
  );
});

const visible = computed(() =>
  props.compact
    ? units.value.length > 1 || forwardsByOrigin.value.size > 0
    : storyJourneys.value.length > 0
);

const journeyStatus = journey =>
  t(`OUTSIDER_CRM.HISTORY.JOURNEY_${journey.status.toUpperCase()}`);

const attemptLabel = forward =>
  t('OUTSIDER_CRM.HISTORY.ATTEMPT', {
    current: forward.attempt_number,
    max: history.value.max_forward_attempts,
  });

const statusLabel = status =>
  t(`OUTSIDER_CRM.STATUS.${String(status).toUpperCase()}`);

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
        class="flex flex-col gap-3 p-3 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-11"
        >
          <span>
            {{
              t('OUTSIDER_CRM.HISTORY.JOURNEY_SINCE', {
                date: formatDate(journey.created_at.slice(0, 10)),
              })
            }}
            · {{ journeyStatus(journey) }}
          </span>
          <span>
            {{
              t('OUTSIDER_CRM.HISTORY.FORWARDS_USED', {
                used: journey.forwards_count,
                max: history.max_forward_attempts,
              })
            }}
          </span>
        </div>

        <ol class="flex flex-col mb-0 list-none">
          <li
            v-for="item in journey.opportunities"
            :key="item.id"
            class="relative flex gap-3 pb-3 last:pb-0 group"
          >
            <span
              class="absolute w-px left-3 top-7 bottom-0 bg-n-weak group-last:hidden"
            />
            <span
              class="z-10 flex items-center justify-center rounded-full size-6 shrink-0"
              :class="STATUS_COLORS[item.status]"
            >
              <Icon
                :icon="
                  item.status === 'forwarded'
                    ? 'i-lucide-forward'
                    : item.status === 'won'
                      ? 'i-lucide-trophy'
                      : item.status === 'lost'
                        ? 'i-lucide-circle-x'
                        : 'i-lucide-handshake'
                "
                class="size-3.5"
              />
            </span>
            <div class="flex flex-col flex-1 min-w-0 gap-1">
              <div
                class="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-sm"
              >
                <span class="font-medium text-n-slate-12">
                  {{ item.business_unit.name }}
                </span>
                <button
                  v-if="item.can_view && item.id !== opportunityId"
                  type="button"
                  class="text-xs text-n-blue-11 hover:underline"
                  @click="emit('open', item)"
                >
                  {{ item.code }}
                </button>
                <span v-else class="text-xs text-n-slate-10">
                  {{ item.code }}
                </span>
                <span
                  class="px-1.5 py-0.5 text-xs rounded-md"
                  :class="STATUS_COLORS[item.status]"
                >
                  {{ statusLabel(item.status) }}
                </span>
                <span
                  v-if="item.id === opportunityId"
                  class="px-1.5 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
                >
                  {{ t('OUTSIDER_CRM.HISTORY.THIS_ONE') }}
                </span>
              </div>
              <span class="text-xs text-n-slate-11">
                {{ formatMoney(item.value_cents) }}
                <template v-if="item.owner"> · {{ item.owner }}</template>
                ·
                {{
                  item.closed_at
                    ? t('OUTSIDER_CRM.HISTORY.CLOSED_ON', {
                        date: formatDate(item.closed_at.slice(0, 10)),
                      })
                    : t('OUTSIDER_CRM.HISTORY.OPEN_SINCE', {
                        date: formatDate(item.created_at.slice(0, 10)),
                      })
                }}
                <template v-if="item.reason && item.status === 'lost'">
                  ·
                  {{
                    t('OUTSIDER_CRM.TIMELINE.LOST_REASON', {
                      reason: item.reason,
                    })
                  }}
                </template>
              </span>

              <div
                v-if="forwardFrom(item.id)"
                class="flex flex-col gap-1 px-2.5 py-2 mt-1 text-xs rounded-lg bg-n-amber-2 text-n-slate-12"
              >
                <span class="flex flex-wrap items-center gap-x-1.5">
                  <Icon
                    icon="i-lucide-arrow-down-right"
                    class="size-3.5 text-n-amber-11"
                  />
                  {{
                    t('OUTSIDER_CRM.HISTORY.FORWARDED_LINE', {
                      unit: forwardFrom(item.id).to_unit,
                      name:
                        forwardFrom(item.id).requested_by ||
                        t('OUTSIDER_CRM.HISTORY.AUTOMATIC'),
                      date: formatDateTime(forwardFrom(item.id).created_at, t),
                    })
                  }}
                  <span class="text-n-amber-11">
                    ({{ attemptLabel(forwardFrom(item.id)) }})
                  </span>
                </span>
                <span
                  v-if="forwardFrom(item.id).reason"
                  class="text-n-slate-11"
                >
                  {{
                    t('OUTSIDER_CRM.HISTORY.REASON', {
                      reason: forwardFrom(item.id).reason,
                    })
                  }}
                </span>
                <span
                  v-if="forwardFrom(item.id).notes"
                  class="pl-2 italic break-words whitespace-pre-wrap border-l-2 border-n-amber-6 text-n-slate-12"
                >
                  {{ forwardFrom(item.id).notes }}
                </span>
              </div>
            </div>
          </li>
        </ol>
      </div>
    </template>
  </div>
</template>
