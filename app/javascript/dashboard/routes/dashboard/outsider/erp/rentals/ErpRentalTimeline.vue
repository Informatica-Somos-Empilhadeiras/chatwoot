<script setup>
// OUTSIDER: linha do tempo de Locação e máquinas (Outsider::Erp::Rentals::ContractDetail / MachineDetail): contrato
// emitido, início e fim, máquina saindo e voltando, faturas de locação, OS e notas. Mais novo em cima; com filters, as
// abas Tudo / OS / Contratos / Notas (ficha da máquina). Evento com registro abre o painel dele.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate, formatMoney } from '../erpStore';
import { displayNumber, shortName, titleCase } from '../records/recordsConfig';
import { contractTypeLabel, hourMeter, machineName } from './rentalHelpers';

const props = defineProps({
  events: { type: Array, default: () => [] },
  filters: { type: Boolean, default: false },
  // painel do contrato: a máquina é o assunto do evento; ficha da máquina: o contrato e o cliente
  subject: { type: String, default: 'machine' },
  canOpen: { type: Function, default: () => true },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const STYLE = {
  contract_created: ['i-lucide-file-signature', 'bg-n-slate-3 text-n-slate-11'],
  contract_start: ['i-lucide-play', 'bg-n-teal-3 text-n-teal-11'],
  contract_due: ['i-lucide-calendar-clock', 'bg-n-amber-3 text-n-amber-11'],
  contract_end: ['i-lucide-flag', 'bg-n-slate-3 text-n-slate-11'],
  contract_status: ['i-lucide-flag', 'bg-n-ruby-3 text-n-ruby-11'],
  machine_out: ['i-lucide-truck', 'bg-n-teal-3 text-n-teal-11'],
  machine_back: ['i-lucide-undo-2', 'bg-n-slate-3 text-n-slate-11'],
  rental_invoice: ['i-lucide-receipt', 'bg-n-blue-3 text-n-blue-11'],
  order: ['i-lucide-wrench', 'bg-n-amber-3 text-n-amber-11'],
  order_delivered: ['i-lucide-package-check', 'bg-n-teal-3 text-n-teal-11'],
  note: ['i-lucide-receipt-text', 'bg-n-blue-3 text-n-blue-11'],
};
const GROUPS = {
  contract_created: 'contracts',
  contract_start: 'contracts',
  contract_due: 'contracts',
  contract_end: 'contracts',
  contract_status: 'contracts',
  machine_out: 'contracts',
  machine_back: 'contracts',
  rental_invoice: 'notes',
  order: 'orders',
  order_delivered: 'orders',
  note: 'notes',
};
const TABS = ['all', 'orders', 'contracts', 'notes'];
const tab = ref('all');

const list = computed(() =>
  [...props.events]
    .reverse()
    .filter(
      event =>
        tab.value === 'all' || (event.group || GROUPS[event.type]) === tab.value
    )
);

const record = event =>
  t(`OUTSIDER_ERP.RECORDS.${String(event.kind).toUpperCase()}.ONE`, {
    number: displayNumber(event),
  });

const titleOf = event =>
  rt(`TIMELINE.${event.type.toUpperCase()}`, {
    record: event.kind ? record(event) : '',
    status: event.status || '',
  });

// o complemento do evento, em pedaços separados por " · "
const detailOf = event => {
  const money = Number(event.total) ? formatMoney(event.total) : '';
  switch (event.type) {
    case 'machine_out':
    case 'machine_back':
      return props.subject === 'machine'
        ? [
            machineName(event),
            event.serie && rt('MACHINE.SERIES_OF', { serie: event.serie }),
          ]
        : [
            record(event),
            contractTypeLabel(t, event.tipo),
            titleCase(event.cliente),
          ];
    case 'rental_invoice':
      return [
        money,
        Number(event.contrato) &&
          rt('CONTRACT.ONE', { number: event.contrato }),
      ];
    case 'order':
      return [
        event.status,
        titleCase(event.atendimento),
        hourMeter(event.horimetro),
        event.name && shortName(event.name),
      ];
    case 'note':
      return [
        money,
        Number(event.pedido) && rt('SALE_OF', { number: event.pedido }),
      ];
    default:
      return [];
  }
};

const clickable = event =>
  event.kind && Number(event.numero) && props.canOpen(event);
const openEvent = event => {
  if (!clickable(event)) return;
  emit(
    'open',
    event.type.startsWith('machine_') && props.subject === 'machine'
      ? {
          kind: 'machines',
          company: event.machine_company,
          numero: event.maquina,
        }
      : event
  );
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-if="filters"
      class="flex self-start items-center p-0.5 rounded-lg bg-n-alpha-2"
      data-rental-timeline-tabs
    >
      <button
        v-for="key in TABS"
        :key="key"
        type="button"
        class="h-7 px-2.5 text-xs rounded-md"
        :class="
          tab === key
            ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="tab = key"
      >
        {{ rt(`TIMELINE.TABS.${key.toUpperCase()}`) }}
      </button>
    </div>
    <p v-if="!list.length" class="mb-0 text-xs text-n-slate-10">
      {{ rt('TIMELINE.EMPTY') }}
    </p>
    <ol class="relative flex flex-col gap-3 pl-0 mb-0 list-none">
      <li
        v-for="(event, index) in list"
        :key="`${event.type}-${event.at}-${index}`"
        class="relative flex gap-3"
      >
        <span
          v-if="index < list.length - 1"
          class="absolute w-px left-3.5 top-7 -bottom-3 bg-n-weak"
        />
        <span
          class="relative z-[1] grid rounded-full size-7 shrink-0 place-content-center"
          :class="(STYLE[event.type] || STYLE.order)[1]"
        >
          <Icon
            :icon="(STYLE[event.type] || STYLE.order)[0]"
            class="size-3.5"
          />
        </span>
        <component
          :is="clickable(event) ? 'button' : 'div'"
          :type="clickable(event) ? 'button' : undefined"
          class="flex flex-col min-w-0 pt-0.5 text-left"
          :class="{ group: clickable(event) }"
          @click="openEvent(event)"
        >
          <span class="text-[13px] leading-snug text-n-slate-12">
            <span
              class="font-medium"
              :class="{ 'group-hover:underline': clickable(event) }"
            >
              {{ titleOf(event) }}
            </span>
            <template v-if="detailOf(event).filter(Boolean).length">
              · {{ detailOf(event).filter(Boolean).join(' · ') }}
            </template>
          </span>
          <span class="text-[11px] tabular-nums text-n-slate-10">
            {{ formatDate(event.at) }}
          </span>
        </component>
      </li>
    </ol>
  </div>
</template>
