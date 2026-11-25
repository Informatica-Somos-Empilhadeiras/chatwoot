<script setup>
// OUTSIDER: a tabela das abas de Locação e máquinas. Contratos: número, cliente, tipo, situação ("vence em N dias" no
// lugar de ATIVO perto do fim), vigência com quantas máquinas e o valor por período. Máquinas: série, máquina (frota
// própria ou do cliente), cliente de agora, situação com o contrato ou a OS, horímetro e a última OS. Faturas de locação:
// número e série, cliente, contrato, situação, emissão e total. Linha fixa; clicar abre o painel; com o painel aberto
// (compact) somem as colunas de apoio. No celular, um cartão por linha.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate, formatMoney, companyName } from '../erpStore';
import {
  KINDS,
  place,
  recordKey,
  relativeDay,
  statusClass,
  titleCase,
} from '../records/recordsConfig';
import {
  contractDue,
  contractTypeClass,
  contractTypeLabel,
  hourMeter,
  machineName,
  machineTag,
  periodKey,
} from './rentalHelpers';

const props = defineProps({
  kind: { type: String, required: true },
  rows: { type: Array, default: () => [] },
  sort: { type: String, default: 'data' },
  direction: { type: String, default: 'desc' },
  selected: { type: String, default: '' },
  loading: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'sort']);

const { t } = useI18n();
const cfg = computed(() => KINDS[props.kind]);
const label = key => t(`OUTSIDER_ERP.RECORDS.${cfg.value.key}.${key}`);
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const contracts = computed(() => props.kind === 'contracts');
const machines = computed(() => props.kind === 'machines');

const short = value => formatDate(value).replace(/\/(\d{2})(\d{2})$/, '/$2');
const clientName = row =>
  titleCase(row.cliente) ||
  (row.cliente_codigo ? `#${row.cliente_codigo}` : '');

const statusText = row => {
  if (contracts.value) {
    const due = contractDue(row);
    if (due) return rt(`DUE.${due.key}`, { n: due.days });
  }
  return row.status;
};
const statusTone = row =>
  contracts.value && contractDue(row)
    ? 'bg-n-amber-3 text-n-amber-11'
    : statusClass(row.status);

// "LOCADA · CT 1038", "EM OS 2080"
const machineLink = row => {
  if (row.status === 'EM OS' && Number(row.os_aberta))
    return rt('MACHINE.ORDER_SHORT', { number: row.os_aberta });
  if (Number(row.contrato))
    return rt('MACHINE.CONTRACT_SHORT', { number: row.contrato });
  return '';
};

const valueOf = row => {
  if (machines.value) return '';
  if (contracts.value && Number(row.parcela)) return formatMoney(row.parcela);
  return Number(row.total) ? formatMoney(row.total) : '—';
};
const valueNote = row => {
  if (!contracts.value || !Number(row.parcela)) return '';
  const key = periodKey(row.periodicidade);
  return key ? rt(key) : rt('INSTALLMENT');
};

const arrow = key => {
  if (props.sort !== key) return '';
  return props.direction === 'asc'
    ? 'i-lucide-arrow-up'
    : 'i-lucide-arrow-down';
};

const TH =
  'py-2.5 font-medium text-[11px] uppercase tracking-wider text-n-slate-10 text-left';
const SORT_BUTTON =
  'inline-flex items-center gap-1 text-[11px] font-medium tracking-wider uppercase hover:text-n-slate-12';
</script>

<template>
  <div class="relative overflow-auto">
    <table
      class="hidden w-full table-fixed md:table"
      :class="compact ? 'min-w-[30rem]' : 'min-w-[50rem]'"
      :data-rental-table="kind"
    >
      <thead class="sticky top-0 z-[1] bg-n-solid-1">
        <tr class="border-b border-n-weak">
          <th :class="TH" class="pl-5 pr-3 w-[7rem]">
            <button
              type="button"
              :class="SORT_BUTTON"
              @click="emit('sort', machines ? 'serie' : 'numero')"
            >
              {{
                machines
                  ? rt('MACHINE.SERIES')
                  : t('OUTSIDER_ERP.RECORDS.NUMBER')
              }}
              <Icon
                v-if="arrow(machines ? 'serie' : 'numero')"
                :icon="arrow(machines ? 'serie' : 'numero')"
                class="size-3"
              />
            </button>
          </th>
          <th v-if="machines" :class="TH" class="px-3">
            {{ rt('MACHINE.MACHINE') }}
          </th>
          <th v-if="!machines || !compact" :class="TH" class="px-3">
            <button
              type="button"
              :class="SORT_BUTTON"
              @click="emit('sort', 'cliente')"
            >
              {{
                machines
                  ? rt('MACHINE.CLIENT_NOW')
                  : t('OUTSIDER_ERP.RECORDS.CLIENT')
              }}
              <Icon
                v-if="arrow('cliente')"
                :icon="arrow('cliente')"
                class="size-3"
              />
            </button>
          </th>
          <th v-if="contracts && !compact" :class="TH" class="px-3 w-[8.5rem]">
            {{ rt('CONTRACT.TYPE') }}
          </th>
          <th
            v-if="kind === 'rental_invoices' && !compact"
            :class="TH"
            class="px-3 w-[7rem]"
          >
            {{ rt('INVOICE.CONTRACT') }}
          </th>
          <th :class="TH" class="px-3 w-[9.5rem]">
            {{ t('OUTSIDER_ERP.RECORDS.STATUS') }}
          </th>
          <th
            :class="TH"
            class="px-3"
            :style="{ width: contracts ? '9rem' : '7rem' }"
          >
            <button
              v-if="!contracts"
              type="button"
              :class="SORT_BUTTON"
              @click="emit('sort', machines ? 'ultima_os' : 'data')"
            >
              {{ label('DATE') }}
              <Icon
                v-if="arrow(machines ? 'ultima_os' : 'data')"
                :icon="arrow(machines ? 'ultima_os' : 'data')"
                class="size-3"
              />
            </button>
            <button
              v-else
              type="button"
              :class="SORT_BUTTON"
              @click="emit('sort', 'termino')"
            >
              {{ label('DATE') }}
              <Icon
                v-if="arrow('termino')"
                :icon="arrow('termino')"
                class="size-3"
              />
            </button>
          </th>
          <th
            v-if="!machines"
            :class="TH"
            class="pl-3 pr-5 !text-right w-[8.5rem]"
          >
            <button
              type="button"
              :class="SORT_BUTTON"
              @click="emit('sort', 'total')"
            >
              <Icon
                v-if="arrow('total')"
                :icon="arrow('total')"
                class="size-3"
              />
              {{ t('OUTSIDER_ERP.RECORDS.TOTAL') }}
            </button>
          </th>
        </tr>
      </thead>
      <tbody :class="{ 'opacity-60': loading }">
        <tr
          v-for="row in rows"
          :key="recordKey(row)"
          class="border-b cursor-pointer border-n-weak last:border-0"
          :class="
            selected === recordKey(row)
              ? 'bg-n-brand/10 shadow-[inset_3px_0_0_rgb(var(--color-brand))]'
              : 'hover:bg-n-alpha-1'
          "
          tabindex="0"
          @click="emit('select', row)"
          @keydown.enter="emit('select', row)"
        >
          <td class="py-2.5 pl-5 pr-3 align-top">
            <div
              class="text-[13px] font-semibold tabular-nums truncate text-n-slate-12"
            >
              {{ machines ? machineTag(row) : row.numero }}
            </div>
            <div class="text-[11px] text-n-slate-10 truncate">
              <template v-if="kind === 'rental_invoices' && row.serie">
                {{ rt('INVOICE.SERIES', { serie: row.serie }) }} ·
              </template>
              {{ companyName(row.banco) }}
            </div>
          </td>
          <td v-if="machines" class="py-2.5 px-3 align-top">
            <div
              class="text-[13px] font-medium truncate text-n-slate-12"
              :title="row.descricao"
            >
              {{ machineName(row) }}
            </div>
            <div class="text-[11px] truncate text-n-slate-10">
              {{
                [
                  Number(row.propria)
                    ? rt('MACHINE.OWN')
                    : rt('MACHINE.CLIENTS'),
                  row.patrimonio &&
                    row.serie &&
                    rt('MACHINE.ASSET_SHORT', { tag: row.patrimonio }),
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </div>
          </td>
          <td v-if="!machines || !compact" class="py-2.5 px-3 align-top">
            <div
              class="text-[13px] font-medium truncate text-n-slate-12"
              :title="row.cliente"
            >
              {{ clientName(row) || '—' }}
            </div>
            <div class="text-[11px] truncate text-n-slate-10">
              {{ place(row) }}
            </div>
          </td>
          <td v-if="contracts && !compact" class="py-2.5 px-3 align-top">
            <span
              class="inline-flex max-w-full px-2 py-0.5 text-[11px] font-medium rounded-md truncate"
              :class="contractTypeClass(row.tipo)"
              :title="row.tipo"
            >
              {{ contractTypeLabel(t, row.tipo) }}
            </span>
          </td>
          <td
            v-if="kind === 'rental_invoices' && !compact"
            class="py-2.5 px-3 align-top text-[13px] tabular-nums text-n-slate-11"
          >
            {{ Number(row.contrato) ? row.contrato : '—' }}
          </td>
          <td class="py-2.5 px-3 align-top">
            <span
              v-if="statusText(row)"
              class="inline-flex max-w-full px-2 py-0.5 text-[11px] font-medium rounded-full truncate"
              :class="statusTone(row)"
              :title="row.status"
            >
              {{ statusText(row) }}
            </span>
            <div
              v-if="machines && machineLink(row)"
              class="mt-1 text-[11px] truncate text-n-slate-10"
            >
              {{ machineLink(row) }}
            </div>
            <div
              v-if="contracts && compact && row.tipo"
              class="mt-1 text-[11px] truncate text-n-slate-10"
            >
              {{ contractTypeLabel(t, row.tipo) }}
            </div>
          </td>
          <td class="py-2.5 px-3 align-top">
            <template v-if="contracts">
              <div
                class="text-[13px] tabular-nums text-n-slate-11 whitespace-nowrap"
              >
                {{ short(row.inicio) || '—' }} {{ rt('CONTRACT.TO') }}
                {{ short(row.termino) || '—' }}
              </div>
              <div class="text-[11px] text-n-slate-10">
                {{
                  t(
                    'OUTSIDER_ERP.RENTALS.CONTRACT.MACHINES',
                    Number(row.maquinas) || 0
                  )
                }}
              </div>
            </template>
            <template v-else-if="machines">
              <div
                class="text-[13px] tabular-nums text-n-slate-11 whitespace-nowrap"
              >
                {{ hourMeter(row.horimetro) || '—' }}
              </div>
              <div class="text-[11px] text-n-slate-10 whitespace-nowrap">
                {{
                  row.ultima_os
                    ? rt('MACHINE.LAST_ORDER', {
                        date: formatDate(row.ultima_os),
                      })
                    : rt('MACHINE.NO_ORDER')
                }}
              </div>
            </template>
            <template v-else>
              <div class="text-[13px] tabular-nums text-n-slate-11">
                {{ formatDate(row.data).slice(0, 5) || '—' }}
              </div>
              <div class="text-[11px] text-n-slate-10">
                {{ relativeDay(t, row.data) || formatDate(row.data).slice(6) }}
              </div>
            </template>
          </td>
          <td
            v-if="!machines"
            class="py-2.5 pl-3 pr-5 text-right align-top tabular-nums whitespace-nowrap"
          >
            <div class="text-[13px] font-medium text-n-slate-12">
              {{ valueOf(row) }}
            </div>
            <div v-if="valueNote(row)" class="text-[11px] text-n-slate-10">
              {{ valueNote(row) }}
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <!-- celular: um cartão por registro -->
    <div class="md:hidden" :class="{ 'opacity-60': loading }">
      <button
        v-for="row in rows"
        :key="recordKey(row)"
        type="button"
        class="flex flex-col w-full gap-1 px-4 py-3 text-left border-b border-n-weak last:border-0"
        :class="
          selected === recordKey(row)
            ? 'bg-n-brand/10 shadow-[inset_3px_0_0_rgb(var(--color-brand))]'
            : 'active:bg-n-alpha-1'
        "
        @click="emit('select', row)"
      >
        <span class="flex items-center w-full gap-2">
          <span class="text-[13px] font-semibold tabular-nums text-n-slate-12">
            {{ machines ? machineTag(row) : row.numero }}
          </span>
          <span class="text-[11px] text-n-slate-10">{{
            companyName(row.banco)
          }}</span>
          <span class="flex-1" />
          <span
            class="text-[13px] font-medium tabular-nums whitespace-nowrap text-n-slate-12"
          >
            {{ machines ? hourMeter(row.horimetro) : valueOf(row) }}
          </span>
        </span>
        <span class="w-full text-[13px] font-medium truncate text-n-slate-12">
          {{ machines ? machineName(row) : clientName(row) }}
        </span>
        <span
          class="flex items-center w-full min-w-0 gap-2 text-[11px] text-n-slate-10"
        >
          <span
            v-if="statusText(row)"
            class="px-2 py-0.5 font-medium rounded-full truncate max-w-[50%]"
            :class="statusTone(row)"
          >
            {{ statusText(row) }}
          </span>
          <span class="truncate">
            {{
              machines
                ? clientName(row) || machineLink(row)
                : contracts
                  ? contractTypeLabel(t, row.tipo)
                  : ''
            }}
          </span>
        </span>
      </button>
    </div>
    <div
      v-if="!rows.length && !loading"
      class="flex flex-col items-center gap-2 p-10 text-center"
    >
      <Icon :icon="cfg.icon" class="size-8 text-n-slate-8" />
      <p class="mb-0 text-sm text-n-slate-11">{{ label('EMPTY') }}</p>
    </div>
  </div>
</template>
