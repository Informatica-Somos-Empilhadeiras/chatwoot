<script setup>
// OUTSIDER: "Vínculos" da ficha da máquina (Outsider::Erp::Rentals::MachineDetail): os cards de contratos, OS, notas e
// faturas são botões. Um clique abre logo abaixo a lista daquele tipo, em cards com o principal de cada um (situação,
// data, cliente, valor); o clique no card abre o detalhe dele (contrato e fatura trocam o painel, com "Voltar"; OS e
// nota abrem o painel de sempre por cima). O tipo aberto fica lembrado por máquina, para o "Voltar" achar a lista aberta.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  formatDate,
  formatMoney,
  companyName,
  isOrderLocked,
} from '../erpStore';
import {
  displayNumber,
  shortName,
  statusClass,
  titleCase,
} from '../records/recordsConfig';
import { contractTypeLabel, hourMeter, machineLinkTabs } from './rentalHelpers';

const props = defineProps({
  detail: { type: Object, required: true },
  canOpen: { type: Function, required: true },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const LIMIT = 6;
const machineKey = computed(
  () => `${props.detail.company}:${props.detail.numero}`
);
const selected = ref(machineLinkTabs.get(machineKey.value) || '');
const showAll = ref(false);

const byDate = (a, b) =>
  String(b.data || '').localeCompare(String(a.data || ''));

// a NFS-e mostra o número da prefeitura quando tem
const notes = computed(() =>
  [
    ...(props.detail.invoices || []).map(row => ({
      ...row,
      kind: 'invoices',
    })),
    ...(props.detail.service_invoices || []).map(row => ({
      ...row,
      kind: 'service_invoices',
      rotulo: Number(row.nfse) > 0 ? String(row.nfse) : null,
    })),
  ].sort(byDate)
);

const groups = computed(() => {
  const orders = props.detail.orders || [];
  const open = orders.filter(
    row => !isOrderLocked({ Situacao: row.status })
  ).length;
  return [
    {
      key: 'CONTRACTS',
      kind: 'contracts',
      icon: 'i-lucide-file-signature',
      rows: props.detail.contracts || [],
    },
    {
      key: 'ORDERS',
      kind: 'orders',
      icon: 'i-lucide-wrench',
      rows: orders,
      note: open ? t('OUTSIDER_ERP.RENTALS.MACHINE.OPEN_ORDERS', open) : '',
    },
    {
      key: 'NOTES',
      kind: 'invoices',
      icon: 'i-lucide-receipt-text',
      rows: notes.value,
    },
    {
      key: 'RENTAL_INVOICES',
      kind: 'rental_invoices',
      icon: 'i-lucide-receipt',
      rows: props.detail.rental_invoices || [],
    },
  ];
});

const current = computed(() =>
  groups.value.find(group => group.key === selected.value && group.rows.length)
);
const visible = computed(() => {
  const rows = current.value?.rows || [];
  return showAll.value ? rows : rows.slice(0, LIMIT);
});

const pick = group => {
  if (!group.rows.length) return;
  selected.value = selected.value === group.key ? '' : group.key;
  showAll.value = false;
  machineLinkTabs.set(machineKey.value, selected.value);
};

const unit = row =>
  row.banco && row.banco !== props.detail.company ? companyName(row.banco) : '';
const money = value => (Number(value) ? formatMoney(value) : '');
const join = parts => parts.filter(Boolean).join(' · ');

// cada linha: { key, ref (o que abre), title, status, lines, amount }
const card = row => {
  switch (selected.value) {
    case 'CONTRACTS':
      return {
        key: `${row.banco}-${row.contrato}-${row.item || ''}`,
        ref: { kind: 'contracts', company: row.banco, numero: row.contrato },
        title: rt('CONTRACT.ONE', { number: row.contrato }),
        status: row.contrato_status,
        lines: [
          join([
            row.tipo && contractTypeLabel(t, row.tipo),
            titleCase(row.cliente) ||
              (row.cliente_codigo ? `#${row.cliente_codigo}` : ''),
            unit(row),
          ]),
          join([
            row.saida && rt('CONTRACT.LEFT', { date: formatDate(row.saida) }),
            row.devolvida
              ? row.retorno &&
                rt('CONTRACT.RETURNED', { date: formatDate(row.retorno) })
              : row.retorno_previsto &&
                rt('CONTRACT.RETURN_DUE', {
                  date: formatDate(row.retorno_previsto),
                }),
          ]),
        ],
        tag: row.devolvida ? rt('CONTRACT.BACK') : '',
        amount: money(row.valor),
      };
    case 'ORDERS':
      return {
        key: `${row.banco}-${row.numero}`,
        ref: { kind: 'orders', company: row.banco, numero: row.numero },
        title: t('OUTSIDER_ERP.RECORDS.ORDERS.ONE', { number: row.numero }),
        status: row.status,
        lines: [
          join([
            formatDate(row.data),
            titleCase(row.atendimento),
            hourMeter(row.horimetro),
          ]),
          join([
            titleCase(row.cliente) ||
              (row.cliente_codigo ? `#${row.cliente_codigo}` : ''),
            row.tecnico_nome && shortName(row.tecnico_nome),
            unit(row),
          ]),
        ],
        amount: money(row.total),
      };
    case 'NOTES':
      return {
        key: `${row.kind}-${row.banco}-${row.numero}`,
        ref: {
          kind: row.kind,
          company: row.banco,
          numero: row.numero,
          rotulo: row.rotulo,
        },
        title: t(
          `OUTSIDER_ERP.RECORDS.${row.kind === 'invoices' ? 'INVOICES' : 'SERVICE_INVOICES'}.ONE`,
          { number: displayNumber(row) }
        ),
        status: row.status,
        lines: [
          join([
            formatDate(row.data),
            Number(row.pedido) && rt('SALE_OF', { number: row.pedido }),
            unit(row),
          ]),
        ],
        amount: money(row.total),
      };
    default:
      return {
        key: `${row.banco}-${row.numero}-${row.serie || ''}`,
        ref: {
          kind: 'rental_invoices',
          company: row.banco,
          numero: row.numero,
        },
        title: t('OUTSIDER_ERP.RECORDS.RENTAL_INVOICES.ONE', {
          number: row.numero,
        }),
        status: row.status,
        lines: [
          join([
            rt('CONTRACT.ISSUED_ON', { date: formatDate(row.data) }),
            row.serie && rt('INVOICE.SERIES', { serie: row.serie }),
            Number(row.contrato) &&
              rt('CONTRACT.ONE', { number: row.contrato }),
            unit(row),
          ]),
        ],
        amount: money(row.total),
      };
  }
};

const cards = computed(() => visible.value.map(card));

const LABEL =
  'text-[11px] font-medium uppercase tracking-wider text-n-slate-10';
const CARD =
  'flex items-start w-full gap-3 px-3 py-2.5 text-left rounded-lg outline outline-1 -outline-offset-1 outline-n-weak bg-n-solid-1 enabled:hover:bg-n-alpha-1 disabled:cursor-default';
</script>

<template>
  <section class="flex flex-col gap-2" data-machine-links>
    <h4 :class="LABEL" class="mb-0">{{ rt('MACHINE.LINKS') }}</h4>
    <div class="grid grid-cols-4 gap-2">
      <button
        v-for="group in groups"
        :key="group.key"
        type="button"
        class="flex flex-col items-center gap-1 px-1 py-2 text-center rounded-lg outline outline-1 -outline-offset-1 transition-colors disabled:cursor-default"
        :class="
          selected === group.key
            ? 'bg-n-teal-2 outline-n-teal-7'
            : 'bg-n-alpha-1 outline-transparent enabled:hover:bg-n-alpha-2'
        "
        :disabled="!group.rows.length"
        :aria-pressed="selected === group.key"
        :aria-controls="`machine-links-${group.key}`"
        :data-machine-link="group.kind"
        @click="pick(group)"
      >
        <Icon
          :icon="group.icon"
          class="size-4"
          :class="selected === group.key ? 'text-n-teal-11' : 'text-n-slate-10'"
        />
        <span class="text-[13px] font-semibold tabular-nums text-n-slate-12">
          {{ group.rows.length }}
        </span>
        <span
          class="flex items-center gap-0.5 text-[11px] leading-tight"
          :class="selected === group.key ? 'text-n-teal-11' : 'text-n-slate-10'"
        >
          {{ rt(`MACHINE.LINK.${group.key}`) }}
          <Icon
            v-if="group.rows.length"
            :icon="
              selected === group.key
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="size-3"
          />
        </span>
        <span v-if="group.note" class="text-[10px] text-n-amber-11">
          {{ group.note }}
        </span>
      </button>
    </div>

    <div
      v-if="current"
      :id="`machine-links-${current.key}`"
      class="flex flex-col gap-2 p-2 mt-1 rounded-xl bg-n-alpha-1"
      :data-machine-link-list="current.kind"
    >
      <div class="flex items-center justify-between gap-2 px-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{
            rt(`MACHINE.LINK_LIST.${current.key}`, { n: current.rows.length })
          }}
        </span>
        <button
          type="button"
          class="grid rounded size-6 place-content-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('OUTSIDER_ERP.CANCEL')"
          @click="pick(current)"
        >
          <Icon icon="i-lucide-x" class="size-3.5" />
        </button>
      </div>
      <button
        v-for="item in cards"
        :key="item.key"
        type="button"
        :class="CARD"
        :disabled="!canOpen(item.ref)"
        data-machine-link-row
        @click="emit('open', item.ref)"
      >
        <div class="flex flex-col flex-1 min-w-0 gap-0.5">
          <span class="flex items-center gap-2 min-w-0">
            <span class="text-[13px] font-medium truncate text-n-slate-12">
              {{ item.title }}
            </span>
            <span
              v-if="item.tag"
              class="px-1.5 py-px text-[10px] font-medium rounded-full shrink-0 bg-n-alpha-2 text-n-slate-11"
            >
              {{ item.tag }}
            </span>
          </span>
          <span
            v-for="(line, index) in item.lines.filter(Boolean)"
            :key="index"
            class="text-xs truncate text-n-slate-10"
          >
            {{ line }}
          </span>
        </div>
        <div class="flex flex-col items-end gap-1 shrink-0">
          <span
            v-if="item.status"
            class="px-2 py-0.5 text-[10px] font-medium rounded-full"
            :class="statusClass(item.status)"
          >
            {{ item.status }}
          </span>
          <span
            v-if="item.amount"
            class="text-[13px] font-medium tabular-nums text-n-slate-12"
          >
            {{ item.amount }}
          </span>
        </div>
      </button>
      <button
        v-if="current.rows.length > LIMIT"
        type="button"
        class="self-start px-1 text-xs text-n-blue-11 hover:underline"
        @click="showAll = !showAll"
      >
        {{
          showAll
            ? t('OUTSIDER_ERP.CONTACT.SHOW_LESS')
            : t('OUTSIDER_ERP.CONTACT.SHOW_ALL', {
                count: current.rows.length,
              })
        }}
      </button>
    </div>
  </section>
</template>
