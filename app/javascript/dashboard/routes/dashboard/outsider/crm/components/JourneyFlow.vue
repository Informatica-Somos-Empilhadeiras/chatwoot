<script setup>
// OUTSIDER: caminho de uma jornada entre unidades, como linha do tempo enxuta: um nó redondo por
// negócio (cor e ícone da situação) com só o nome do negócio, o valor e a unidade embaixo. O resto
// (código, situação, responsável, datas, motivo da perda, e no traço entre dois nós o
// encaminhamento: tentativa, quem, quando, motivo e observação) aparece num cartão ao passar o mouse
// ou ao clicar, que fixa o cartão até clicar fora. Cada linha segue os encaminhamentos de origem para
// destino; negócio aberto direto noutra unidade na mesma jornada começa outra linha. Com o repasse em
// sequência ligado, as próximas unidades aparecem como nós tracejados depois do negócio aberto. Os
// dados vêm do histórico do contato (ContactHistory).
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  STATUS_COLORS,
  formatDate,
  formatDateTime,
  formatMoney,
  formatMoneyShort,
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
const cardRef = ref(null);

const STATUS_ICONS = {
  open: 'i-lucide-handshake',
  won: 'i-lucide-trophy',
  lost: 'i-lucide-x',
  forwarded: 'i-lucide-forward',
};

// nó cheio na cor da situação
const NODE_COLORS = {
  open: 'bg-n-blue-9 text-white',
  won: 'bg-n-teal-9 text-white',
  lost: 'bg-n-ruby-9 text-white',
  forwarded: 'bg-n-amber-9 text-white',
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

// linhas: cada negócio que não chegou por encaminhamento começa uma, que segue pelos
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

// cada linha vira uma sequência de nós; o traço entre dois nós é encaminhamento (laranja), próximo
// do repasse (tracejado) ou só continuação
const lines = computed(() =>
  rows.value.map((steps, rowIndex) => {
    const nodes = steps.map(step => ({
      key: `deal-${step.item.id}`,
      item: step.item,
      next: step.forward ? 'forward' : null,
      forward: step.forward,
    }));
    if (rowIndex === upcomingRow.value) {
      nodes[nodes.length - 1].next = 'upcoming';
      upcoming.value.forEach((unit, index) => {
        nodes.push({
          key: `next-${unit.id}`,
          unit,
          next: index < upcoming.value.length - 1 ? 'upcoming' : null,
        });
      });
    }
    return nodes;
  })
);

const SEGMENT_CLASSES = {
  forward: 'border-t-2 border-n-amber-8',
  upcoming: 'border-t-2 border-dashed border-n-slate-7',
};

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

// cartão de detalhes: segue o mouse; um clique fixa
const hovered = ref(null);
const pinned = ref(null);
const position = ref({ top: 0, left: 0 });
const detail = computed(() => pinned.value || hovered.value);

const place = target => {
  const box = target.getBoundingClientRect();
  const width = 256;
  position.value = {
    top: box.bottom + 8,
    left: Math.max(
      8,
      Math.min(
        window.innerWidth - width - 8,
        box.left + box.width / 2 - width / 2
      )
    ),
  };
};

const show = (event, entry) => {
  if (pinned.value) return;
  place(event.currentTarget);
  hovered.value = entry;
};

const hide = () => {
  hovered.value = null;
};

const isSame = (a, b) => a && b && a.kind === b.kind && a.id === b.id;

const toggle = (event, entry) => {
  if (isSame(pinned.value, entry)) {
    pinned.value = null;
    return;
  }
  place(event.currentTarget);
  pinned.value = entry;
  hovered.value = null;
};

const isActive = entry => isSame(detail.value, entry);

onClickOutside(cardRef, event => {
  if (!pinned.value) return;
  if (event.target.closest?.('[data-journey-node], [data-journey-link]'))
    return;
  pinned.value = null;
});

const nodeEntry = item => ({ kind: 'deal', id: item.id, item });
const linkEntry = forward => ({ kind: 'forward', id: forward.id, forward });
const upcomingEntry = unit => ({ kind: 'upcoming', id: unit.id, unit });

const openDeal = item => {
  pinned.value = null;
  hovered.value = null;
  emit('open', item);
};

// caminho maior que o espaço: rola só o necessário para o negócio da tela ficar à vista
const showCurrent = async () => {
  await nextTick();
  const container = scrollRef.value;
  const current = container?.querySelector('[data-current]');
  if (!container || !current) return;
  container.scrollLeft = Math.max(
    0,
    current.offsetLeft + current.offsetWidth + 48 - container.clientWidth
  );
};

onMounted(showCurrent);
watch(() => [props.opportunityId, props.journey], showCurrent);
</script>

<template>
  <div class="flex flex-col gap-2" data-journey-flow>
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

    <div ref="scrollRef" class="flex flex-col gap-4 pt-1 pb-1 overflow-x-auto">
      <div
        v-for="(nodes, rowIndex) in lines"
        :key="nodes[0].key"
        class="flex flex-col gap-1"
      >
        <span v-if="rowIndex" class="text-[11px] text-n-slate-10">
          {{ t('OUTSIDER_CRM.JOURNEY.PARALLEL') }}
        </span>
        <div class="flex items-start w-max">
          <template v-for="(node, index) in nodes" :key="node.key">
            <div
              class="relative flex flex-col items-center w-32 gap-1.5 px-1 text-center shrink-0"
              :data-current="node.item?.id === opportunityId || undefined"
            >
              <!-- traços até o nó anterior e o próximo, por trás do círculo -->
              <span
                v-if="index"
                class="absolute left-0 right-1/2 top-5"
                :class="SEGMENT_CLASSES[nodes[index - 1].next]"
              />
              <span
                v-if="node.next"
                class="absolute left-1/2 right-0 top-5"
                :class="SEGMENT_CLASSES[node.next]"
              />

              <!-- negócio: só nome, valor e unidade -->
              <template v-if="node.item">
                <button
                  type="button"
                  class="relative z-[1] grid transition-transform rounded-full size-10 place-content-center hover:scale-110 focus:outline-none focus-visible:ring-4 focus-visible:ring-n-brand"
                  :class="[
                    NODE_COLORS[node.item.status],
                    {
                      'ring-4 ring-n-blue-5': node.item.id === opportunityId,
                      'ring-4 ring-n-slate-6':
                        node.item.id !== opportunityId &&
                        isActive(nodeEntry(node.item)),
                    },
                  ]"
                  :aria-label="node.item.title"
                  data-journey-node
                  @mouseenter="show($event, nodeEntry(node.item))"
                  @mouseleave="hide"
                  @focus="show($event, nodeEntry(node.item))"
                  @blur="hide"
                  @click="toggle($event, nodeEntry(node.item))"
                >
                  <Icon :icon="STATUS_ICONS[node.item.status]" class="size-4" />
                </button>
                <span
                  class="w-full text-xs font-medium leading-tight truncate text-n-slate-12"
                  :title="node.item.title"
                >
                  {{ node.item.title }}
                </span>
                <span
                  class="text-xs font-semibold leading-none text-n-slate-12"
                >
                  {{ formatMoneyShort(node.item.value_cents) }}
                </span>
                <span
                  class="w-full text-[11px] leading-tight truncate text-n-slate-11"
                  :title="node.item.business_unit.name"
                >
                  {{ node.item.business_unit.name }}
                </span>
              </template>

              <!-- próxima unidade do repasse -->
              <template v-else>
                <button
                  type="button"
                  class="relative z-[1] grid border-2 border-dashed rounded-full size-10 place-content-center bg-n-solid-1 border-n-slate-7 text-n-slate-10 hover:border-n-slate-9 focus:outline-none"
                  :aria-label="node.unit.name"
                  data-journey-node
                  @mouseenter="show($event, upcomingEntry(node.unit))"
                  @mouseleave="hide"
                  @focus="show($event, upcomingEntry(node.unit))"
                  @blur="hide"
                  @click="toggle($event, upcomingEntry(node.unit))"
                >
                  <Icon icon="i-lucide-building-2" class="size-4" />
                </button>
                <span
                  class="w-full text-xs leading-tight truncate text-n-slate-11"
                  :title="node.unit.name"
                >
                  {{ node.unit.name }}
                </span>
                <span class="text-[11px] leading-tight text-n-slate-10">
                  {{ t('OUTSIDER_CRM.JOURNEY.UPCOMING') }}
                </span>
              </template>
            </div>

            <!-- marca do encaminhamento no meio do traço -->
            <span v-if="node.forward" class="relative w-0 shrink-0">
              <button
                type="button"
                class="absolute z-[2] grid -translate-x-1/2 rounded-full size-5 top-[10px] place-content-center bg-n-amber-9 text-white hover:scale-110 transition-transform focus:outline-none focus-visible:ring-n-brand"
                :aria-label="
                  t('OUTSIDER_CRM.FORWARD.TO_UNIT', {
                    unit: node.forward.to_unit,
                  })
                "
                data-journey-link
                @mouseenter="show($event, linkEntry(node.forward))"
                @mouseleave="hide"
                @focus="show($event, linkEntry(node.forward))"
                @blur="hide"
                @click="toggle($event, linkEntry(node.forward))"
              >
                <Icon icon="i-lucide-chevron-right" class="size-3.5" />
              </button>
            </span>
          </template>
        </div>
      </div>
    </div>

    <Teleport to="body">
      <div
        v-if="detail"
        ref="cardRef"
        class="fixed z-[60] w-64 p-3 text-sm rounded-xl shadow-lg bg-n-solid-2 outline outline-1 outline-n-container"
        :class="{ 'pointer-events-none': !pinned }"
        :style="{ top: `${position.top}px`, left: `${position.left}px` }"
        data-journey-card
      >
        <template v-if="detail.kind === 'deal'">
          <div class="flex items-start justify-between gap-2">
            <span class="font-medium leading-snug text-n-slate-12">
              {{ detail.item.title }}
            </span>
            <span
              class="px-1.5 py-0.5 text-[11px] rounded-md shrink-0"
              :class="STATUS_COLORS[detail.item.status]"
            >
              {{ statusLabel(detail.item.status) }}
            </span>
          </div>
          <dl
            class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 mt-2 mb-0 text-xs"
          >
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.UNIT') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">
              {{ detail.item.business_unit.name }}
            </dd>
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.VALUE') }}
            </dt>
            <dd class="mb-0 font-semibold text-n-slate-12">
              {{ formatMoney(detail.item.value_cents) }}
            </dd>
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.OWNER') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">
              {{ detail.item.owner || t('OUTSIDER_CRM.CLAIM.NO_OWNER') }}
            </dd>
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.CODE') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">{{ detail.item.code }}</dd>
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.WHEN') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">{{ dates(detail.item) }}</dd>
            <template
              v-if="detail.item.reason && detail.item.status !== 'open'"
            >
              <dt class="text-n-slate-11">
                {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.REASON') }}
              </dt>
              <dd class="mb-0 text-n-ruby-11">{{ detail.item.reason }}</dd>
            </template>
          </dl>
          <span
            v-if="detail.item.id === opportunityId"
            class="inline-block px-1.5 py-0.5 mt-2 text-[11px] rounded-md bg-n-blue-3 text-n-blue-11"
          >
            {{ t('OUTSIDER_CRM.HISTORY.THIS_ONE') }}
          </span>
          <button
            v-else-if="detail.item.can_view"
            type="button"
            class="inline-flex items-center gap-1 mt-2 text-xs font-medium text-n-blue-11 hover:underline"
            data-journey-open
            @click="openDeal(detail.item)"
          >
            {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.OPEN') }}
            <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
          </button>
          <p v-if="!pinned" class="mt-2 mb-0 text-[11px] text-n-slate-10">
            {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.CLICK_TO_PIN') }}
          </p>
        </template>

        <template v-else-if="detail.kind === 'forward'">
          <span class="font-medium text-n-slate-12">
            {{
              t('OUTSIDER_CRM.FORWARD.TO_UNIT', {
                unit: detail.forward.to_unit,
              })
            }}
          </span>
          <dl
            class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 mt-2 mb-0 text-xs"
          >
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.ATTEMPT') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">
              {{
                maxAttempts
                  ? t('OUTSIDER_CRM.JOURNEY.DETAIL.ATTEMPT_OF', {
                      current: detail.forward.attempt_number,
                      max: maxAttempts,
                    })
                  : detail.forward.attempt_number
              }}
            </dd>
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.WHO') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">
              {{ forwardBy(detail.forward) }}
            </dd>
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.WHEN') }}
            </dt>
            <dd class="mb-0 text-n-slate-12">
              {{ formatDateTime(detail.forward.created_at, t) }}
            </dd>
            <template v-if="detail.forward.reason">
              <dt class="text-n-slate-11">
                {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.REASON') }}
              </dt>
              <dd class="mb-0 text-n-slate-12">{{ detail.forward.reason }}</dd>
            </template>
          </dl>
          <p
            v-if="detail.forward.notes"
            class="pl-2 mt-2 mb-0 text-xs italic border-l-2 text-n-slate-12 border-n-amber-7"
          >
            {{ detail.forward.notes }}
          </p>
        </template>

        <template v-else>
          <span class="font-medium text-n-slate-12">{{
            detail.unit.name
          }}</span>
          <p class="mt-1 mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.JOURNEY.DETAIL.UPCOMING_HELP') }}
          </p>
        </template>
      </div>
    </Teleport>
  </div>
</template>
