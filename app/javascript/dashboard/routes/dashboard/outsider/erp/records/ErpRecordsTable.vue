<script setup>
// OUTSIDER: a tabela de uma aba da seção ERP. Linha fixa (o hover só muda o fundo), número + unidade, cliente + cidade
// (na OS, a máquina), situação, vendedor/técnico, data (na OS, a previsão, em vermelho quando atrasada) e total.
// Clicar abre o painel de detalhe; os títulos com seta ordenam. Com o painel aberto (compact) some a coluna da pessoa
// e a tabela cabe sem rolar de lado.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate, formatMoney } from '../erpStore';
import {
  KINDS,
  initials,
  isLate,
  place,
  recordKey,
  relativeDay,
  shortName,
  statusClass,
  titleCase,
} from './recordsConfig';

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

const dateOf = row => (props.kind === 'orders' ? row.previsao : row.data);
const late = row =>
  props.kind === 'orders' &&
  row.previsao &&
  !row.entrega &&
  isLate(row.previsao) &&
  !['FECHADA', 'CANCELADA', 'PERDIDA'].includes(String(row.status || ''));

const subline = row => {
  if (props.kind === 'orders')
    return [row.equipamento, row.serie && `${t('OUTSIDER_ERP.RECORDS.SERIES')} ${row.serie}`]
      .filter(Boolean)
      .join(' · ') || place(row);
  return place(row);
};

const arrow = key => {
  if (props.sort !== key) return '';
  return props.direction === 'asc' ? 'i-lucide-arrow-up' : 'i-lucide-arrow-down';
};

const TH =
  'py-2.5 font-medium text-[11px] uppercase tracking-wider text-n-slate-10 text-left';
</script>

<template>
  <div class="relative overflow-auto">
    <table
      class="hidden w-full table-fixed md:table"
      :class="compact ? 'min-w-[30rem]' : 'min-w-[46rem]'"
    >
      <thead class="sticky top-0 z-[1] bg-n-solid-1">
        <tr class="border-b border-n-weak">
          <th :class="TH" class="pl-5 pr-3" :style="{ width: compact ? '5.5rem' : '6.5rem' }">
            <button
              type="button"
              class="inline-flex items-center gap-1 text-[11px] font-medium tracking-wider uppercase hover:text-n-slate-12"
              @click="emit('sort', 'numero')"
            >
              {{ t('OUTSIDER_ERP.RECORDS.NUMBER') }}
              <Icon v-if="arrow('numero')" :icon="arrow('numero')" class="size-3" />
            </button>
          </th>
          <th :class="TH" class="px-3">
            <button
              type="button"
              class="inline-flex items-center gap-1 text-[11px] font-medium tracking-wider uppercase hover:text-n-slate-12"
              @click="emit('sort', 'cliente')"
            >
              {{ t('OUTSIDER_ERP.RECORDS.CLIENT') }}
              <Icon v-if="arrow('cliente')" :icon="arrow('cliente')" class="size-3" />
            </button>
          </th>
          <th :class="TH" class="px-3" :style="{ width: compact ? '8.5rem' : '9.5rem' }">
            {{ t('OUTSIDER_ERP.RECORDS.STATUS') }}
          </th>
          <th v-if="!compact" :class="TH" class="w-[10.5rem] px-3">
            {{ label('PERSON') }}
          </th>
          <th :class="TH" class="px-3" :style="{ width: compact ? '5.5rem' : '6.5rem' }">
            <button
              type="button"
              class="inline-flex items-center gap-1 text-[11px] font-medium tracking-wider uppercase hover:text-n-slate-12"
              @click="emit('sort', 'data')"
            >
              {{ label('DATE') }}
              <Icon v-if="arrow('data')" :icon="arrow('data')" class="size-3" />
            </button>
          </th>
          <th :class="TH" class="pl-3 pr-5 !text-right" :style="{ width: compact ? '7.5rem' : '8.5rem' }">
            <button
              type="button"
              class="inline-flex items-center gap-1 text-[11px] font-medium tracking-wider uppercase hover:text-n-slate-12"
              @click="emit('sort', 'total')"
            >
              <Icon v-if="arrow('total')" :icon="arrow('total')" class="size-3" />
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
            <div class="text-[13px] font-semibold tabular-nums text-n-slate-12">
              {{ row.numero }}
            </div>
            <div class="text-[11px] text-n-slate-10 truncate">{{ row.banco }}</div>
          </td>
          <td class="py-2.5 px-3 align-top">
            <div
              class="text-[13px] font-medium truncate text-n-slate-12"
              :title="row.cliente"
            >
              {{ titleCase(row.cliente) || `#${row.cliente_codigo}` }}
            </div>
            <div class="text-[11px] truncate text-n-slate-10">
              {{ subline(row) }}
            </div>
          </td>
          <td class="py-2.5 px-3 align-top">
            <span
              v-if="row.status"
              class="inline-flex max-w-full px-2 py-0.5 text-[11px] font-medium rounded-full truncate"
              :class="statusClass(row.status)"
            >
              {{ row.status }}
            </span>
            <div
              v-if="kind === 'orders' && row.substatus"
              class="mt-1 text-[11px] truncate text-n-slate-10"
              :title="row.substatus"
            >
              {{ row.substatus }}
            </div>
            <div
              v-else-if="kind === 'sales' && row.nota"
              class="mt-1 text-[11px] text-n-slate-10"
            >
              {{ t('OUTSIDER_ERP.RECORDS.INVOICE', { number: row.nota }) }}
            </div>
          </td>
          <td v-if="!compact" class="py-2.5 px-3 align-top">
            <div
              v-if="row.pessoa"
              class="flex items-center min-w-0 gap-2 text-[13px] text-n-slate-11"
            >
              <span
                class="grid text-[10px] font-semibold rounded-full shrink-0 size-6 place-content-center bg-n-alpha-2 text-n-slate-11"
              >
                {{ initials(row.pessoa) }}
              </span>
              <span class="truncate" :title="row.pessoa">
                {{ shortName(row.pessoa) }}
              </span>
            </div>
            <span v-else class="text-[13px] text-n-slate-9">—</span>
          </td>
          <td class="py-2.5 px-3 align-top">
            <div
              class="text-[13px] tabular-nums"
              :class="late(row) ? 'text-n-ruby-11 font-medium' : 'text-n-slate-11'"
            >
              {{ formatDate(dateOf(row)).slice(0, 5) || '—' }}
            </div>
            <div
              class="text-[11px]"
              :class="late(row) ? 'text-n-ruby-11' : 'text-n-slate-10'"
            >
              {{
                late(row)
                  ? t('OUTSIDER_ERP.RECORDS.LATE')
                  : relativeDay(t, dateOf(row)) ||
                    formatDate(dateOf(row)).slice(6)
              }}
            </div>
          </td>
          <td
            class="py-2.5 pl-3 pr-5 text-[13px] font-medium text-right align-top tabular-nums whitespace-nowrap text-n-slate-12"
          >
            {{ Number(row.total) ? formatMoney(row.total) : '—' }}
          </td>
        </tr>
      </tbody>
    </table>
    <!-- celular: um cartão por registro (a tabela não cabe) -->
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
            {{ row.numero }}
          </span>
          <span class="text-[11px] text-n-slate-10">{{ row.banco }}</span>
          <span class="flex-1" />
          <span
            class="text-[13px] font-medium tabular-nums whitespace-nowrap text-n-slate-12"
          >
            {{ Number(row.total) ? formatMoney(row.total) : '—' }}
          </span>
        </span>
        <span class="w-full text-[13px] font-medium truncate text-n-slate-12">
          {{ titleCase(row.cliente) || `#${row.cliente_codigo}` }}
        </span>
        <span class="flex items-center w-full min-w-0 gap-2 text-[11px] text-n-slate-10">
          <span
            v-if="row.status"
            class="px-2 py-0.5 font-medium rounded-full truncate max-w-[45%]"
            :class="statusClass(row.status)"
          >
            {{ row.status }}
          </span>
          <span v-if="row.pessoa" class="truncate">
            {{ shortName(row.pessoa) }}
          </span>
          <span
            class="ml-auto tabular-nums whitespace-nowrap"
            :class="{ 'text-n-ruby-11 font-medium': late(row) }"
          >
            {{ formatDate(dateOf(row)) || '—' }}
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
