<script setup>
// OUTSIDER: corpo da ficha da máquina (Outsider::Erp::Rentals::MachineDetail): dados técnicos, onde ela está agora
// (contrato ativo com o cliente, OS aberta, disponível na Somos ou com o dono), o dono quando é do cliente, os vínculos
// (contratos, OS, notas e faturas: ErpMachineLinks, clicáveis) e a linha do tempo da máquina com as abas Tudo / OS / Contratos / Notas.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpRentalTimeline from './ErpRentalTimeline.vue';
import ErpMachineLinks from './ErpMachineLinks.vue';
import { formatDate, formatMoney, companyName } from '../erpStore';
import { titleCase } from '../records/recordsConfig';
import { contractTypeLabel, hourMeter } from './rentalHelpers';

const props = defineProps({
  detail: { type: Object, required: true },
  canOpen: { type: Function, required: true },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const h = computed(() => props.detail.header || {});
const now = computed(() => props.detail.agora || {});

const specs = computed(() =>
  [
    ['CAPACITY', h.value.capacidade],
    ['LIFT', h.value.elevacao],
    ['MAST', h.value.mastro],
    ['MAST_HEIGHT', h.value.altura_mastro],
    ['YEAR', Number(h.value.ano) ? String(h.value.ano) : ''],
    ['VOLTAGE', h.value.voltagem],
    ['WHEELS', h.value.rodas],
    ['HOURMETER', hourMeter(h.value.horimetro)],
    ['MODEL', h.value.modelo !== h.value.descricao ? h.value.modelo : ''],
    [
      'RENTAL_VALUE',
      Number(h.value.valor_locacao) ? formatMoney(h.value.valor_locacao) : '',
    ],
    ['WARRANTY', formatDate(h.value.garantia)],
    ['IN_OPERATION', formatDate(h.value.inicio_operacao)],
    ['PURCHASE_INVOICE', h.value.nf_aquisicao],
  ]
    .map(([key, text]) => [key, String(text || '').trim()])
    .filter(([, text]) => text && text !== '0')
);

const place = computed(() => {
  const contract = now.value.contrato;
  if (contract)
    return {
      kind: 'contract',
      client: titleCase(contract.cliente) || `#${contract.cliente_codigo}`,
      line: [
        contract.saida &&
          rt('CONTRACT.LEFT', { date: formatDate(contract.saida) }),
        contract.retorno_previsto &&
          rt('CONTRACT.RETURN_DUE', {
            date: formatDate(contract.retorno_previsto),
          }),
        Number(contract.valor) && formatMoney(contract.valor),
      ]
        .filter(Boolean)
        .join(' · '),
    };
  if (now.value.situacao === 'DISPONÍVEL') return { kind: 'available' };
  if (now.value.situacao === 'DO CLIENTE') return { kind: 'owner' };
  return null;
});

const owner = computed(() => props.detail.dono || {});

const LABEL =
  'text-[11px] font-medium uppercase tracking-wider text-n-slate-10';
</script>

<template>
  <div class="flex flex-col gap-5" data-machine-body>
    <dl
      v-if="specs.length"
      class="grid grid-cols-2 gap-x-4 gap-y-3 mb-0 sm:grid-cols-3"
    >
      <div v-for="[key, text] in specs" :key="key" class="min-w-0">
        <dt :class="LABEL">{{ rt(`MACHINE.FIELDS.${key}`) }}</dt>
        <dd class="mb-0 text-[13px] text-n-slate-12 break-words">{{ text }}</dd>
      </div>
    </dl>

    <section class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">{{ rt('MACHINE.NOW') }}</h4>
      <div
        class="flex flex-col gap-1 px-3 py-2.5 rounded-lg bg-n-alpha-1 text-[13px] text-n-slate-12"
      >
        <template v-if="place?.kind === 'contract'">
          <span>
            <span class="font-medium">{{ place.client }}</span>
            ·
            <button
              type="button"
              class="text-n-teal-11 hover:underline"
              @click="
                emit('open', {
                  kind: 'contracts',
                  company: now.contrato.banco,
                  numero: now.contrato.contrato,
                })
              "
            >
              {{ rt('CONTRACT.ONE', { number: now.contrato.contrato }) }}
            </button>
            ({{ contractTypeLabel(t, now.contrato.tipo) }})
          </span>
          <span v-if="place.line" class="text-xs text-n-slate-11">{{
            place.line
          }}</span>
        </template>
        <span v-else-if="place?.kind === 'available'">{{
          rt('MACHINE.AVAILABLE')
        }}</span>
        <span v-else-if="place?.kind === 'owner'">{{
          rt('MACHINE.AT_OWNER')
        }}</span>
        <button
          v-if="now.os"
          type="button"
          class="inline-flex items-center self-start gap-1.5 text-xs font-medium text-n-amber-11 hover:underline disabled:no-underline"
          :disabled="!canOpen({ kind: 'orders' })"
          @click="
            emit('open', {
              kind: 'orders',
              company: now.os.banco,
              numero: now.os.numero,
            })
          "
        >
          <Icon icon="i-lucide-wrench" class="size-3.5" />
          {{
            rt('MACHINE.OPEN_ORDER', {
              number: now.os.numero,
              unit: companyName(now.os.banco),
            })
          }}
        </button>
      </div>
    </section>

    <section v-if="owner.nome" class="flex flex-col gap-1">
      <h4 :class="LABEL" class="mb-0">{{ rt('MACHINE.OWNER') }}</h4>
      <span class="text-[13px] text-n-slate-12">
        {{ titleCase(owner.nome) }}
        <span class="text-n-slate-10">
          · {{ [owner.cidade, owner.uf].filter(Boolean).join('/') }}
        </span>
      </span>
    </section>

    <ErpMachineLinks
      :detail="detail"
      :can-open="canOpen"
      @open="node => emit('open', node)"
    />

    <section
      v-if="h.descricao_tecnica || h.acessorios"
      class="flex flex-col gap-2"
    >
      <h4 :class="LABEL" class="mb-0">{{ rt('MACHINE.TECH') }}</h4>
      <p class="mb-0 text-[13px] whitespace-pre-line text-n-slate-12">
        {{ [h.descricao_tecnica, h.acessorios].filter(Boolean).join('\n') }}
      </p>
    </section>

    <section class="flex flex-col gap-2">
      <h4 :class="LABEL" class="mb-0">{{ rt('MACHINE.TIMELINE') }}</h4>
      <ErpRentalTimeline
        :events="detail.timeline || []"
        filters
        subject="contract"
        :can-open="canOpen"
        @open="node => emit('open', node)"
      />
    </section>
  </div>
</template>
