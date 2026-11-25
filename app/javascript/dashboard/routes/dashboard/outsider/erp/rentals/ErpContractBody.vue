<script setup>
// OUTSIDER: corpo do painel do contrato (Outsider::Erp::Rentals::ContractDetail): vigência, prazo, valor, faturamento,
// pagamento e vendedor; endereço de entrega; as máquinas do contrato (saída, retorno e a situação de agora, cada uma abre
// a ficha); as faturas de locação; as OS das máquinas desde o início; observações e a linha do tempo do contrato.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpRentalTimeline from './ErpRentalTimeline.vue';
import { formatDate, formatMoney } from '../erpStore';
import { shortName, statusClass, titleCase } from '../records/recordsConfig';
import { machineName, periodKey } from './rentalHelpers';

const props = defineProps({
  detail: { type: Object, required: true },
  canOpen: { type: Function, required: true },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const h = computed(() => props.detail.header || {});

const duration = computed(() => {
  if (Number(h.value.meses)) return rt('CONTRACT.MONTHS', { n: h.value.meses });
  if (Number(h.value.dias)) return rt('CONTRACT.DAYS', { n: h.value.dias });
  return '';
});
const value = computed(() => {
  if (Number(h.value.parcela)) {
    const key = periodKey(h.value.periodicidade);
    return `${formatMoney(h.value.parcela)}${key ? ` ${rt(key)}` : ''}`;
  }
  return Number(h.value.total) ? formatMoney(h.value.total) : '';
});

const facts = computed(() =>
  [
    [
      'VALIDITY',
      h.value.inicio || h.value.termino
        ? `${formatDate(h.value.inicio) || '—'} ${rt('CONTRACT.TO')} ${formatDate(h.value.termino) || '—'}`
        : '',
    ],
    ['DURATION', duration.value],
    ['VALUE', value.value],
    [
      'TOTAL',
      Number(h.value.parcela) && Number(h.value.total)
        ? formatMoney(h.value.total)
        : '',
    ],
    [
      'BILLING',
      Number(h.value.dia_faturamento)
        ? rt('CONTRACT.EVERY_DAY', { day: h.value.dia_faturamento })
        : '',
    ],
    ['NEXT_INVOICE', formatDate(props.detail.proxima_fatura)],
    ['PAYMENT', h.value.pagamento],
    ['SELLER', h.value.vendedor_nome ? shortName(h.value.vendedor_nome) : ''],
    ['CONTACT', h.value.contato],
    ['ISSUED', formatDate(h.value.data)],
  ].filter(([, text]) => text)
);

const delivery = computed(() =>
  [
    [h.value.entrega_endereco, h.value.entrega_numero]
      .filter(Boolean)
      .join(', '),
    h.value.entrega_bairro,
    [h.value.entrega_cidade, h.value.entrega_uf].filter(Boolean).join('/'),
    h.value.obra && rt('CONTRACT.SITE', { name: h.value.obra }),
  ]
    .filter(Boolean)
    .join(' · ')
);

const machines = computed(() => props.detail.maquinas || []);
const invoices = computed(() => props.detail.faturas || []);
const orders = computed(() => props.detail.ordens || []);

const machineLine = row =>
  [
    row.saida && rt('CONTRACT.LEFT', { date: formatDate(row.saida) }),
    row.devolvida
      ? rt('CONTRACT.RETURNED', { date: formatDate(row.retorno) })
      : row.retorno_previsto &&
        rt('CONTRACT.RETURN_DUE', { date: formatDate(row.retorno_previsto) }),
    Number(row.valor) && formatMoney(row.valor),
  ]
    .filter(Boolean)
    .join(' · ');

const openMachine = row =>
  emit('open', {
    kind: 'machines',
    company: row.base,
    numero: row.maquina,
    label: machineName(row),
  });

const LABEL =
  'text-[11px] font-medium uppercase tracking-wider text-n-slate-10';
const CARD =
  'flex items-start w-full gap-3 px-3 py-2.5 text-left rounded-lg outline outline-1 -outline-offset-1 outline-n-weak bg-n-solid-1';
</script>

<template>
  <div class="flex flex-col gap-5" data-contract-body>
    <dl class="grid grid-cols-2 gap-x-4 gap-y-3 mb-0 sm:grid-cols-3">
      <div v-for="[key, text] in facts" :key="key" class="min-w-0">
        <dt :class="LABEL">{{ rt(`CONTRACT.FIELDS.${key}`) }}</dt>
        <dd class="mb-0 text-[13px] text-n-slate-12 break-words">{{ text }}</dd>
      </div>
    </dl>

    <section v-if="delivery" class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">{{ rt('CONTRACT.DELIVERY') }}</h4>
      <p
        class="px-3 py-2 mb-0 text-[13px] rounded-lg bg-n-alpha-1 text-n-slate-12"
      >
        {{ titleCase(delivery) }}
      </p>
    </section>

    <section class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">
        {{ rt('CONTRACT.MACHINES_TITLE', { n: machines.length }) }}
      </h4>
      <p v-if="!machines.length" class="mb-0 text-xs text-n-slate-10">
        {{ rt('CONTRACT.NO_MACHINES') }}
      </p>
      <button
        v-for="row in machines"
        :key="`${row.item}-${row.maquina}`"
        type="button"
        :class="CARD"
        class="hover:bg-n-alpha-1"
        :disabled="!Number(row.maquina)"
        @click="openMachine(row)"
      >
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-[13px] font-medium text-n-teal-11">
            {{ machineName(row) }}
            <span v-if="row.serie" class="font-normal text-n-slate-11">
              · {{ rt('MACHINE.SERIES_OF', { serie: row.serie }) }}
            </span>
          </span>
          <span class="text-xs text-n-slate-10">{{ machineLine(row) }}</span>
        </div>
        <span
          class="px-2 py-0.5 text-[11px] font-medium rounded-full shrink-0"
          :class="
            row.devolvida
              ? 'bg-n-alpha-2 text-n-slate-11'
              : statusClass(row.situacao)
          "
        >
          {{ row.devolvida ? rt('CONTRACT.BACK') : row.situacao }}
        </span>
      </button>
    </section>

    <section v-if="invoices.length" class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">{{ rt('CONTRACT.INVOICES') }}</h4>
      <button
        v-for="row in invoices"
        :key="`${row.numero}-${row.serie}`"
        type="button"
        :class="CARD"
        class="hover:bg-n-alpha-1"
        @click="
          emit('open', {
            kind: 'rental_invoices',
            company: detail.company,
            numero: row.numero,
          })
        "
      >
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-[13px] text-n-slate-12">
            {{
              t('OUTSIDER_ERP.RECORDS.RENTAL_INVOICES.ONE', {
                number: row.numero,
              })
            }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              [
                rt('CONTRACT.ISSUED_ON', { date: formatDate(row.data) }),
                Number(row.maquinas) &&
                  t(
                    'OUTSIDER_ERP.RENTALS.CONTRACT.MACHINES',
                    Number(row.maquinas)
                  ),
              ]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
        </div>
        <div class="flex flex-col items-end gap-1 shrink-0">
          <span class="text-[13px] font-medium tabular-nums text-n-slate-12">
            {{ formatMoney(row.total) }}
          </span>
          <span
            v-if="row.status"
            class="px-2 py-0.5 text-[10px] font-medium rounded-full"
            :class="statusClass(row.status)"
          >
            {{ row.status }}
          </span>
        </div>
      </button>
    </section>

    <section v-if="orders.length" class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">{{ rt('CONTRACT.ORDERS') }}</h4>
      <button
        v-for="row in orders"
        :key="`${row.banco}-${row.numero}`"
        type="button"
        class="flex items-center gap-2 text-left text-[13px] text-n-slate-12 hover:underline disabled:no-underline"
        :disabled="!canOpen({ kind: 'orders' })"
        @click="
          emit('open', {
            kind: 'orders',
            company: row.banco,
            numero: row.numero,
          })
        "
      >
        <Icon
          icon="i-lucide-wrench"
          class="size-3.5 text-n-slate-10 shrink-0"
        />
        <span class="truncate">
          {{
            [
              t('OUTSIDER_ERP.RECORDS.ORDERS.ONE', { number: row.numero }),
              formatDate(row.data),
              titleCase(row.atendimento),
            ]
              .filter(Boolean)
              .join(' · ')
          }}
        </span>
        <span
          v-if="row.status"
          class="px-2 py-0.5 ml-auto text-[10px] font-medium rounded-full shrink-0"
          :class="statusClass(row.status)"
        >
          {{ row.status }}
        </span>
      </button>
    </section>

    <section v-if="h.observacoes" class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">
        {{ t('OUTSIDER_ERP.RECORDS.FIELDS.NOTES') }}
      </h4>
      <p class="mb-0 text-[13px] whitespace-pre-line text-n-slate-12">
        {{ h.observacoes }}
      </p>
    </section>

    <section v-if="detail.timeline?.length" class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">{{ rt('CONTRACT.TIMELINE') }}</h4>
      <ErpRentalTimeline
        :events="detail.timeline"
        subject="machine"
        :can-open="canOpen"
        @open="node => emit('open', node)"
      />
    </section>
  </div>
</template>
