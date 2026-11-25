<script setup>
// OUTSIDER: painel de detalhe de Locação e máquinas (/outsider/erp/records/(contracts|machines|rental_invoices)/:empresa/:n):
// cabeçalho, "Abrir conversa" e o corpo de cada tipo (contrato, ficha da máquina, fatura de locação). Contrato, máquina e
// fatura clicados dentro do painel trocam o painel aqui mesmo, com "Voltar"; OS, pedido e notas abrem o painel de
// sempre (ErpRecordPanel) por cima, sem sair da aba. Só leitura.
import { ref, computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { frontendURL } from 'dashboard/helper/URLHelper';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpRecordPanel from '../records/ErpRecordPanel.vue';
import ErpContractBody from './ErpContractBody.vue';
import ErpMachineBody from './ErpMachineBody.vue';
import ErpRentalInvoiceBody from './ErpRentalInvoiceBody.vue';
import { allows } from '../../access/accessStore';
import { erpErrorMessage, companyName } from '../erpStore';
import {
  KINDS,
  SCREENS,
  place,
  statusClass,
  titleCase,
} from '../records/recordsConfig';
import {
  contractDue,
  contractTypeLabel,
  machineName,
  periodKey,
} from './rentalHelpers';

const props = defineProps({
  kind: { type: String, required: true },
  company: { type: String, required: true },
  number: { type: Number, required: true },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const route = useRoute();
const rt = (key, values) => t(`OUTSIDER_ERP.RENTALS.${key}`, values || {});

const view = ref({
  kind: props.kind,
  company: props.company,
  number: props.number,
});
const trail = ref([]);
const detail = ref(null);
const loading = ref(true);
const failure = ref('');
// OS, pedido ou nota aberta por cima
const floating = ref(null);

const header = computed(() => detail.value?.header || {});
const client = computed(() => detail.value?.cliente || {});

const cache = new Map();
const cacheKey = record => `${record.kind}:${record.company}:${record.number}`;
let ticket = 0;
const load = async () => {
  ticket += 1;
  const mine = ticket;
  const record = { ...view.value };
  failure.value = '';
  loading.value = !cache.has(cacheKey(record));
  detail.value = cache.get(cacheKey(record)) || null;
  try {
    const { data } = await ErpAPI.record(
      record.kind,
      record.company,
      record.number
    );
    cache.set(cacheKey(record), data);
    if (mine === ticket) detail.value = data;
  } catch (error) {
    if (mine !== ticket || detail.value) return;
    failure.value =
      error?.response?.status === 404
        ? t('OUTSIDER_ERP.RECORDS.NOT_FOUND')
        : erpErrorMessage(t, error);
  } finally {
    if (mine === ticket) loading.value = false;
  }
};
load();

const RENTAL_KINDS = ['contracts', 'machines', 'rental_invoices'];

// rótulo curto de um registro (para o "Voltar")
const recordLabel = record => {
  if (record.kind === 'machines')
    return record.label || rt('MACHINE.ONE', { number: record.number });
  return t(`OUTSIDER_ERP.RECORDS.${KINDS[record.kind].key}.ONE`, {
    number: record.number,
  });
};

const canOpen = node => {
  const screen = SCREENS[node.kind];
  return Boolean(screen) && allows(screen);
};

// ref: { kind, company, numero, rotulo?, label? }
const open = node => {
  if (!node?.kind || !Number(node.numero) || !canOpen(node)) return;
  const record = {
    kind: node.kind,
    company: node.company || view.value.company,
    number: Number(node.numero),
    label: node.label,
    rotulo: node.rotulo,
  };
  if (cacheKey(record) === cacheKey(view.value)) return;
  if (!RENTAL_KINDS.includes(record.kind)) {
    floating.value = record;
    return;
  }
  const index = trail.value.findIndex(
    item => cacheKey(item) === cacheKey(record)
  );
  if (index >= 0) trail.value = trail.value.slice(0, index);
  else
    trail.value = [
      ...trail.value,
      {
        ...view.value,
        label: view.value.kind === 'machines' ? machineName(header.value) : '',
      },
    ];
  view.value = record;
  load();
};

const back = () => {
  const previous = trail.value[trail.value.length - 1];
  if (!previous) return;
  trail.value = trail.value.slice(0, -1);
  view.value = previous;
  load();
};

const title = computed(() => {
  if (view.value.kind === 'machines')
    return detail.value
      ? machineName(header.value)
      : rt('MACHINE.ONE', { number: view.value.number });
  return recordLabel(view.value);
});

const status = computed(() => {
  if (view.value.kind === 'machines') return header.value.situacao;
  return header.value.status;
});
const statusText = computed(() => {
  const due = view.value.kind === 'contracts' && contractDue(header.value);
  return due ? rt(`DUE.${due.key}`, { n: due.days }) : status.value;
});

const subtitle = computed(() => {
  const h = header.value;
  const unit = companyName(view.value.company);
  if (view.value.kind === 'machines')
    return [
      h.serie && rt('MACHINE.SERIES_OF', { serie: h.serie }),
      h.patrimonio && rt('MACHINE.ASSET_OF', { tag: h.patrimonio }),
      Number(h.propria) ? rt('MACHINE.OWN') : rt('MACHINE.CLIENTS'),
      unit,
    ]
      .filter(Boolean)
      .join(' · ');
  const clientName =
    titleCase(client.value.nome) ||
    (h.cliente_codigo ? `#${h.cliente_codigo}` : '');
  const parts =
    view.value.kind === 'contracts'
      ? [
          contractTypeLabel(t, h.tipo),
          periodKey(h.periodicidade) && rt(`${periodKey(h.periodicidade)}_ADJ`),
        ]
      : [];
  return [...parts, clientName, place(client.value), unit]
    .filter(Boolean)
    .join(' · ');
});

const chatUrl = computed(() => {
  const accountId = route.params.accountId;
  if (detail.value?.conversation_id)
    return frontendURL(
      `accounts/${accountId}/conversations/${detail.value.conversation_id}`
    );
  if (detail.value?.contact_id)
    return frontendURL(
      `accounts/${accountId}/contacts/${detail.value.contact_id}`
    );
  return '';
});
</script>

<template>
  <aside
    class="fixed inset-y-0 right-0 z-40 flex flex-col w-full max-w-[32rem] border-l shadow-xl shrink-0 bg-n-solid-2 border-n-weak xl:shadow-none xl:static xl:z-auto xl:w-[30rem] xl:ml-4 xl:mb-4 xl:rounded-xl xl:border"
    :data-rental-panel="view.kind"
  >
    <header class="px-5 pt-4 pb-3 border-b border-n-weak">
      <button
        v-if="trail.length"
        type="button"
        class="flex items-center gap-1 mb-2 -ml-1 px-1 py-0.5 text-xs font-medium rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
        @click="back"
      >
        <Icon icon="i-lucide-arrow-left" class="size-3.5" />
        {{
          t('OUTSIDER_ERP.RECORDS.BACK_TO', {
            record: recordLabel(trail[trail.length - 1]),
          })
        }}
      </button>
      <div class="flex items-start gap-2">
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="mb-0 text-lg font-semibold text-n-slate-12">
              {{ title }}
            </h3>
            <span
              v-if="statusText"
              class="px-2 py-0.5 text-[11px] font-medium rounded-full"
              :class="
                statusText !== status
                  ? 'bg-n-amber-3 text-n-amber-11'
                  : statusClass(status)
              "
            >
              {{ statusText }}
            </span>
          </div>
          <span class="text-[13px] text-n-slate-11">{{ subtitle }}</span>
        </div>
        <Button
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          :aria-label="t('OUTSIDER_ERP.CANCEL')"
          @click="emit('close')"
        />
      </div>
      <div v-if="chatUrl" class="flex flex-wrap gap-2 mt-3">
        <a
          :href="chatUrl"
          class="inline-flex items-center gap-1.5 h-8 px-3 text-xs font-medium rounded-lg bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
        >
          <Icon icon="i-lucide-message-circle" class="size-3.5" />
          {{
            detail?.conversation_id
              ? t('OUTSIDER_ERP.RECORDS.OPEN_CHAT')
              : t('OUTSIDER_ERP.RECORDS.OPEN_CONTACT')
          }}
        </a>
      </div>
    </header>

    <div class="flex-1 min-h-0 px-5 py-4 overflow-y-auto">
      <div v-if="loading && !detail" class="flex justify-center p-8">
        <Spinner class="text-n-slate-10" />
      </div>
      <div
        v-else-if="failure && !detail"
        class="flex flex-col items-center gap-3 p-6 text-center"
      >
        <Icon icon="i-lucide-cloud-off" class="size-8 text-n-slate-9" />
        <p class="mb-0 text-sm text-n-slate-11">{{ failure }}</p>
        <Button
          size="sm"
          variant="faded"
          color="slate"
          :label="t('OUTSIDER_ERP.CONTACT.RETRY')"
          @click="load"
        />
      </div>
      <template v-else-if="detail">
        <ErpContractBody
          v-if="view.kind === 'contracts'"
          :detail="detail"
          :can-open="canOpen"
          @open="open"
        />
        <ErpMachineBody
          v-else-if="view.kind === 'machines'"
          :detail="detail"
          :can-open="canOpen"
          @open="open"
        />
        <ErpRentalInvoiceBody v-else :detail="detail" @open="open" />
      </template>
    </div>

    <ErpRecordPanel
      v-if="floating"
      :key="`${floating.kind}:${floating.company}:${floating.number}`"
      :kind="floating.kind"
      :company="floating.company"
      :number="floating.number"
      floating
      @close="floating = null"
    />
  </aside>
</template>
