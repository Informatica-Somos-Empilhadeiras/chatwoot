<script setup>
// OUTSIDER: corpo do painel da fatura de locação (Outsider::Erp::Rentals::RentalInvoiceDetail): emissão, período,
// vendedor e série; os contratos que ela cobra e as máquinas cobradas (cada um abre o painel dele). É um documento do
// contrato, não é nota fiscal.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDate, formatMoney } from '../erpStore';
import { shortName, statusClass } from '../records/recordsConfig';
import { contractTypeLabel, machineName } from './rentalHelpers';

const props = defineProps({
  detail: { type: Object, required: true },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const h = computed(() => props.detail.header || {});
const range = (from, to) =>
  from || to
    ? `${formatDate(from) || '—'} ${rt('CONTRACT.TO')} ${formatDate(to) || '—'}`
    : '';

const facts = computed(() =>
  [
    ['ISSUED', formatDate(h.value.data)],
    ['TOTAL', Number(h.value.total) ? formatMoney(h.value.total) : ''],
    ['PERIOD', range(h.value.inicio, h.value.termino)],
    ['SERIES', h.value.serie ? String(h.value.serie) : ''],
    ['SELLER', h.value.vendedor_nome ? shortName(h.value.vendedor_nome) : ''],
  ].filter(([, text]) => text)
);

const LABEL =
  'text-[11px] font-medium uppercase tracking-wider text-n-slate-10';
const CARD =
  'flex items-start w-full gap-3 px-3 py-2.5 text-left rounded-lg outline outline-1 -outline-offset-1 outline-n-weak bg-n-solid-1 hover:bg-n-alpha-1';
</script>

<template>
  <div class="flex flex-col gap-5" data-rental-invoice-body>
    <p class="mb-0 text-xs text-n-slate-10">{{ rt('INVOICE.HINT') }}</p>
    <dl class="grid grid-cols-2 gap-x-4 gap-y-3 mb-0 sm:grid-cols-3">
      <div v-for="[key, text] in facts" :key="key" class="min-w-0">
        <dt :class="LABEL">{{ rt(`INVOICE.FIELDS.${key}`) }}</dt>
        <dd class="mb-0 text-[13px] text-n-slate-12">{{ text }}</dd>
      </div>
    </dl>

    <section v-if="detail.contratos?.length" class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">{{ rt('INVOICE.CONTRACTS') }}</h4>
      <button
        v-for="row in detail.contratos"
        :key="row.contrato"
        type="button"
        :class="CARD"
        @click="
          emit('open', {
            kind: 'contracts',
            company: detail.company,
            numero: row.contrato,
          })
        "
      >
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-[13px] font-medium text-n-teal-11">
            {{ rt('CONTRACT.ONE', { number: row.contrato }) }} ·
            {{ contractTypeLabel(t, row.tipo) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ range(row.inicio, row.termino) }}
          </span>
        </div>
        <span
          v-if="row.contrato_status"
          class="px-2 py-0.5 text-[11px] font-medium rounded-full shrink-0"
          :class="statusClass(row.contrato_status)"
        >
          {{ row.contrato_status }}
        </span>
      </button>
    </section>

    <section v-if="detail.maquinas?.length" class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">
        {{ rt('INVOICE.MACHINES', { n: detail.maquinas.length }) }}
      </h4>
      <button
        v-for="row in detail.maquinas"
        :key="`${row.contrato}-${row.item}-${row.maquina}`"
        type="button"
        :class="CARD"
        :disabled="!Number(row.maquina)"
        @click="
          emit('open', {
            kind: 'machines',
            company: row.base,
            numero: row.maquina,
            label: machineName(row),
          })
        "
      >
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-[13px] font-medium text-n-teal-11">
            {{ machineName(row) }}
            <span v-if="row.serie" class="font-normal text-n-slate-11">
              · {{ rt('MACHINE.SERIES_OF', { serie: row.serie }) }}
            </span>
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              [
                rt('CONTRACT.ONE', { number: row.contrato }),
                range(row.inicio, row.termino),
              ]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
        </div>
      </button>
    </section>
  </div>
</template>
