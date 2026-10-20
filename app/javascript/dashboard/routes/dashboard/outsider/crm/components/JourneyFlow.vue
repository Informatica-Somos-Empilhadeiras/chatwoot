<script setup>
// OUTSIDER: caminho de uma jornada entre unidades, em diagrama horizontal: um quadro por negócio
// (unidade, código, situação, valor, responsável, datas e motivo da perda), ligados por setas com a
// tentativa, quem encaminhou (ou "automático") e o motivo; destino e observação aparecem ao passar o
// mouse. Cada linha segue os encaminhamentos de origem para destino; negócio aberto direto noutra
// unidade na mesma jornada começa outra linha. Com o repasse em sequência ligado, as próximas
// unidades aparecem tracejadas depois do negócio aberto ("se perder"). Os dados vêm do histórico do
// contato (ContactHistory).
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  STATUS_COLORS,
  formatDate,
  formatDateTime,
  formatMoney,
} from '../helpers';

const props = defineProps({
  journey: { type: Object, required: true },
  maxAttempts: { type: Number, default: 0 },
  // negócio aberto na tela: destacado e sem link
  opportunityId: { type: Number, default: null },
});

const emit = defineEmits(['open']);

const { t } = useI18n();

const scrollRef = ref(null);

const STATUS_ICONS = {
  open: 'i-lucide-handshake',
  won: 'i-lucide-trophy',
  lost: 'i-lucide-circle-x',
  forwarded: 'i-lucide-forward',
};

const forwardsByOrigin = computed(
  () =>
    new Map(
      props.journey.forwards.map(forward => [
        forward.from_opportunity_id,
        forward,
      ])
    )
);

const byId = computed(
  () => new Map(props.journey.opportunities.map(item => [item.id, item]))
);

// linhas do diagrama: cada negócio que não chegou por encaminhamento começa uma, que segue pelos
// encaminhamentos até o último destino
const rows = computed(() => {
  const targets = new Set(
    props.journey.forwards.map(forward => forward.to_opportunity_id)
  );
  const seen = new Set();
  const follow = start => {
    const steps = [];
    let item = start;
    while (item && !seen.has(item.id)) {
      seen.add(item.id);
      const forward = forwardsByOrigin.value.get(item.id);
      steps.push({ item, forward });
      item = forward && byId.value.get(forward.to_opportunity_id);
    }
    return steps;
  };
  const list = props.journey.opportunities
    .filter(item => !targets.has(item.id))
    .map(follow);
  // destino cuja origem não veio na lista: fica numa linha própria, para não sumir
  props.journey.opportunities
    .filter(item => !seen.has(item.id))
    .forEach(item => list.push(follow(item)));
  return list;
});

const upcoming = computed(() => props.journey.upcoming || []);

// as próximas unidades vão depois da linha do negócio aberto que o repasse levaria adiante
const upcomingRow = computed(() => {
  if (!upcoming.value.length) return -1;
  const index = rows.value.findIndex(steps =>
    steps.some(step => step.item.id === props.journey.upcoming_from)
  );
  return index === -1 ? rows.value.length - 1 : index;
});

const day = timestamp => formatDate(String(timestamp).slice(0, 10));

const statusLabel = status =>
  t(`OUTSIDER_CRM.STATUS.${String(status).toUpperCase()}`);

const dates = item =>
  item.closed_at
    ? t('OUTSIDER_CRM.HISTORY.CLOSED_ON', { date: day(item.closed_at) })
    : t('OUTSIDER_CRM.HISTORY.OPEN_SINCE', { date: day(item.created_at) });

const forwardBy = forward =>
  forward.requested_by
    ? t('OUTSIDER_CRM.JOURNEY.BY', { name: forward.requested_by })
    : t('OUTSIDER_CRM.JOURNEY.AUTOMATIC');

const forwardTooltip = forward =>
  [
    t('OUTSIDER_CRM.FORWARD.TO_UNIT', { unit: forward.to_unit }),
    formatDateTime(forward.created_at, t),
    forward.reason &&
      t('OUTSIDER_CRM.HISTORY.REASON', { reason: forward.reason }),
    forward.notes,
  ]
    .filter(Boolean)
    .join(' · ');

// caminho maior que o espaço: rola só o necessário para o negócio da tela ficar à vista (o começo
// do caminho fica visível sempre que der)
const showCurrent = async () => {
  await nextTick();
  const container = scrollRef.value;
  const current = container?.querySelector('[data-current]');
  if (!container || !current) return;
  container.scrollLeft = Math.max(
    0,
    current.offsetLeft + current.offsetWidth + 24 - container.clientWidth
  );
};

onMounted(showCurrent);
watch(() => [props.opportunityId, props.journey], showCurrent);
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-11"
    >
      <span>
        {{
          t('OUTSIDER_CRM.HISTORY.JOURNEY_SINCE', {
            date: day(journey.created_at),
          })
        }}
        ·
        {{ t(`OUTSIDER_CRM.HISTORY.JOURNEY_${journey.status.toUpperCase()}`) }}
      </span>
      <span v-if="maxAttempts">
        {{
          t('OUTSIDER_CRM.HISTORY.FORWARDS_USED', {
            used: journey.forwards_count,
            max: maxAttempts,
          })
        }}
      </span>
    </div>

    <div
      ref="scrollRef"
      class="relative flex flex-col gap-3 pb-2 overflow-x-auto"
    >
      <div
        v-for="(steps, rowIndex) in rows"
        :key="steps[0].item.id"
        class="flex flex-col gap-1"
      >
        <span v-if="rowIndex" class="text-[11px] text-n-slate-10">
          {{ t('OUTSIDER_CRM.JOURNEY.PARALLEL') }}
        </span>
        <div class="flex items-stretch w-max">
          <template v-for="step in steps" :key="step.item.id">
            <div
              class="flex flex-col w-40 gap-1 p-3 rounded-xl shrink-0 bg-n-solid-1 outline -outline-offset-1"
              :class="
                step.item.id === opportunityId
                  ? 'outline-2 outline-n-blue-8'
                  : 'outline-1 outline-n-weak'
              "
              :data-current="step.item.id === opportunityId || undefined"
            >
              <div class="flex items-center gap-1.5 min-w-0">
                <span
                  class="flex items-center justify-center rounded-full size-5 shrink-0"
                  :class="STATUS_COLORS[step.item.status]"
                >
                  <Icon :icon="STATUS_ICONS[step.item.status]" class="size-3" />
                </span>
                <span
                  class="text-sm font-medium truncate text-n-slate-12"
                  :title="step.item.business_unit.name"
                >
                  {{ step.item.business_unit.name }}
                </span>
              </div>
              <div class="flex flex-wrap items-center gap-1.5 text-xs">
                <button
                  v-if="step.item.can_view && step.item.id !== opportunityId"
                  type="button"
                  class="text-xs text-n-blue-11 hover:underline"
                  @click="emit('open', step.item)"
                >
                  {{ step.item.code }}
                </button>
                <span v-else class="text-n-slate-11">{{ step.item.code }}</span>
                <span
                  class="px-1.5 py-0.5 rounded-md"
                  :class="STATUS_COLORS[step.item.status]"
                >
                  {{ statusLabel(step.item.status) }}
                </span>
              </div>
              <span class="text-sm font-semibold text-n-slate-12">
                {{ formatMoney(step.item.value_cents) }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{ step.item.owner || t('OUTSIDER_CRM.CLAIM.NO_OWNER') }}
              </span>
              <span class="text-xs text-n-slate-10">{{
                dates(step.item)
              }}</span>
              <span
                v-if="step.item.reason && step.item.status !== 'open'"
                class="text-xs text-n-ruby-11 line-clamp-2"
              >
                {{ step.item.reason }}
              </span>
              <span
                v-if="step.item.id === opportunityId"
                class="self-start px-1.5 py-0.5 mt-auto text-[11px] rounded-md bg-n-blue-3 text-n-blue-11"
              >
                {{ t('OUTSIDER_CRM.HISTORY.THIS_ONE') }}
              </span>
            </div>

            <div
              v-if="step.forward"
              v-tooltip="forwardTooltip(step.forward)"
              class="flex flex-col items-center justify-center w-20 gap-0.5 px-1 text-center shrink-0"
            >
              <span class="text-[11px] font-medium text-n-amber-11">
                {{
                  t('OUTSIDER_CRM.HISTORY.ATTEMPT', {
                    current: step.forward.attempt_number,
                    max: maxAttempts,
                  })
                }}
              </span>
              <span class="flex items-center w-full text-n-amber-9">
                <span class="flex-1 h-px bg-current" />
                <Icon icon="i-lucide-chevron-right" class="-ms-1.5 size-4" />
              </span>
              <span class="text-[11px] text-n-slate-11 line-clamp-2">
                {{ forwardBy(step.forward) }}
                <Icon
                  v-if="step.forward.notes"
                  icon="i-lucide-message-square-text"
                  class="inline-block size-3 align-[-2px]"
                />
              </span>
            </div>
          </template>

          <template v-if="rowIndex === upcomingRow">
            <template
              v-for="(unit, index) in upcoming"
              :key="`next-${unit.id}`"
            >
              <div
                class="flex flex-col items-center justify-center w-20 gap-0.5 px-1 text-center shrink-0"
              >
                <span class="text-[11px] text-n-slate-10">
                  {{
                    index
                      ? t('OUTSIDER_CRM.JOURNEY.THEN')
                      : t('OUTSIDER_CRM.JOURNEY.IF_LOST')
                  }}
                </span>
                <span class="flex items-center w-full text-n-slate-8">
                  <span class="flex-1 border-t border-dashed border-current" />
                  <Icon icon="i-lucide-chevron-right" class="-ms-1.5 size-4" />
                </span>
              </div>
              <div
                class="flex flex-col justify-center w-32 gap-1 p-3 border border-dashed rounded-xl shrink-0 border-n-slate-7"
              >
                <span
                  class="text-sm font-medium truncate text-n-slate-11"
                  :title="unit.name"
                >
                  {{ unit.name }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ t('OUTSIDER_CRM.JOURNEY.UPCOMING') }}
                </span>
              </div>
            </template>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
