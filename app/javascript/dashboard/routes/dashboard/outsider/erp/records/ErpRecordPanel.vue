<script setup>
// OUTSIDER: painel de detalhe da seção ERP (/outsider/erp/records/:kind/:empresa/:número): cabeçalho, ações, a corrente
// orçamento -> OS -> pedido (nós clicáveis), dados, cliente, itens e totais (ErpRecordItems; na OS, com a conferência do
// estoque e "Liberar para separação") e a linha do tempo. Orçamento: Editar (só em
// NEGOCIAÇÃO e fechado no Mais Prático), Ver PDF, Enviar e Copiar, pela gaveta do orçamento, e "Converter em OS"
// (ErpQuoteConvertDialog, em NEGOCIAÇÃO, sem OS e sem pedido, na unidade liberada). OS: a edição de sempre
// (ErpOrderEditor), travada quando a OS está fechada. Pedido: técnico e OS informados no chat (ErpSaleAttribution, só
// no Chatwoot). Notas (NF-e, NFS-e): só leitura. Um nó da corrente troca o
// painel aqui mesmo (sem mudar de aba), com "Voltar" para o registro anterior.
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpRecordChain from './ErpRecordChain.vue';
import ErpRecordItems from './ErpRecordItems.vue';
import ErpRecordTimeline from './ErpRecordTimeline.vue';
import ErpSaleAttribution from './ErpSaleAttribution.vue';
import ErpOrderEditor from '../components/ErpOrderEditor.vue';
import ErpBudgetDrawer from '../budgets/ErpBudgetDrawer.vue';
import ErpPdfDialog from '../budgets/ErpPdfDialog.vue';
import ErpDocumentSendDialog from '../components/ErpDocumentSendDialog.vue';
import ErpClientChat from './ErpClientChat.vue';
import ErpOrderScheduleDialog from '../components/ErpOrderScheduleDialog.vue';
import ErpQuoteConvertDialog from '../orders/ErpQuoteConvertDialog.vue';
import { isNegotiation } from '../orders/orderHelpers';
import { useOrderReady } from '../components/orderReady';
import { fetchCloud, cloudKey, CLOUD_KINDS } from './invoiceCloud';
import { budgetErrorMessage } from '../budgets/budgetHelpers';
import { allows } from '../../access/accessStore';
import {
  erpState,
  erpErrorMessage,
  formatDate,
  isOrderLocked,
  reportTypeName,
  orderConcluded,
  orderSchedulable,
  companyName,
} from '../erpStore';
import {
  KINDS,
  displayNumber,
  isLate,
  place,
  statusClass,
  titleCase,
} from './recordsConfig';

const props = defineProps({
  kind: { type: String, required: true },
  company: { type: String, required: true },
  number: { type: Number, required: true },
  // aberto por cima de outra tela (relatório dos técnicos): gaveta fixa à direita em qualquer largura
  floating: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'changed']);

const { t } = useI18n();
const route = useRoute();
const detail = ref(null);
const loading = ref(true);
const failure = ref('');
const busy = ref('');
const drawerRef = ref(null);
const pdfRef = ref(null);

// o registro mostrado: começa no da lista; os nós da corrente trocam aqui, e o caminho guarda os anteriores
const view = ref({
  kind: props.kind,
  company: props.company,
  number: props.number,
});
const trail = ref([]);
const viewKind = computed(() => view.value.kind);
const header = computed(() => detail.value?.header || {});
const client = computed(() => detail.value?.cliente || {});
const recordLabel = record =>
  t(`OUTSIDER_ERP.RECORDS.${KINDS[record.kind].key}.ONE`, {
    number: displayNumber(record),
  });
// a NFS-e só sabe o número da prefeitura depois que carrega
const title = computed(() => {
  const h = header.value;
  const rotulo =
    view.value.rotulo ||
    (viewKind.value === 'service_invoices' && detail.value
      ? (Number(h.nfse) && String(h.nfse)) || (Number(h.rps) && `RPS ${h.rps}`)
      : '');
  return recordLabel({ ...view.value, rotulo });
});

// detalhes já abertos voltam na hora pelo "Voltar"; uma resposta atrasada de outro registro é descartada
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
    // sem rede na volta: fica o que já estava aberto
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

const show = record => {
  view.value = record;
  load();
};

// nó da corrente: abre no painel; se já está no caminho, volta até ele (sem empilhar ida e volta)
const openNode = node => {
  const record = {
    kind: node.kind,
    company: node.company || view.value.company,
    number: node.numero,
    rotulo: node.rotulo,
  };
  const index = trail.value.findIndex(
    item => cacheKey(item) === cacheKey(record)
  );
  if (index >= 0) trail.value = trail.value.slice(0, index);
  else trail.value = [...trail.value, { ...view.value }];
  show(record);
};

const back = () => {
  const previous = trail.value[trail.value.length - 1];
  if (!previous) return;
  trail.value = trail.value.slice(0, -1);
  show(previous);
};

const refresh = () => {
  cache.clear();
  load();
  emit('changed');
};

const name = (code, fullName) => {
  if (fullName) return titleCase(fullName);
  return code ? `#${code}` : '';
};

// dados do cabeçalho por tipo: [rótulo, valor]; vazio não aparece
const facts = computed(() => {
  const h = header.value;
  const lists = {
    quotes: [
      ['SELLER', name(h.vendedor, h.vendedor_nome)],
      ['STARTED_BY', name(h.iniciado_por, h.iniciado_por_nome)],
      ['CREATED', formatDate(h.data)],
      ['VALIDITY', h.validade],
      ['PAYMENT', h.pagamento],
      ['DELIVERY_TIME', h.prazo_entrega],
      ['WARRANTY', h.garantia],
      ['ATTENTION', h.contato],
      ['AUTHORIZED_BY', name(h.autorizado_por, h.autorizado_por_nome)],
    ],
    orders: [
      ['TECHNICIAN', name(h.tecnico, h.tecnico_nome)],
      ['SELLER', name(h.vendedor, h.vendedor_nome)],
      ['ENTRY', formatDate(h.data)],
      ['FORECAST', formatDate(h.previsao)],
      ['DELIVERED', formatDate(h.entrega)],
      ['ATTENDANCE', h.atendimento],
      ['SUBSTATUS', h.substatus],
      ['EQUIPMENT', h.equipamento],
      ['SERIES', h.serie],
      ['HOURMETER', h.horimetro],
      ['ATTENTION', h.contato],
    ],
    sales: [
      ['SELLER', name(h.vendedor, h.vendedor_nome)],
      ['CREATED', formatDate(h.data)],
      ['PAYMENT', h.pagamento],
      ['INVOICED_AT', formatDate(h.faturado_em)],
      ['DELIVERED', formatDate(h.entrega)],
      ['ATTENTION', h.contato],
    ],
    invoices: [
      ['ISSUED', formatDate(h.data)],
      ['NATURE', titleCase(h.natureza)],
      [
        'DIRECTION',
        h.tipo === null || h.tipo === undefined
          ? ''
          : t(
              `OUTSIDER_ERP.RECORDS.FIELDS.DIRECTION_${Number(h.tipo) === 1 ? 'IN' : 'OUT'}`
            ),
      ],
      ['FISCAL_SERIES', h.serie ? String(h.serie) : ''],
      ['CFOP', h.cfop],
      ['OUT_DATE', formatDate(h.saida)],
      ['SELLER', name(h.vendedor, h.vendedor_nome)],
      ['PAYMENT', h.pagamento],
      ['PROTOCOL', h.protocolo],
      ['CANCELED_AT', formatDate(h.data_cancelamento)],
    ],
    service_invoices: [
      ['ISSUED', formatDate(h.data)],
      ['NFSE_NUMBER', Number(h.nfse) ? String(h.nfse) : ''],
      ['RPS', Number(h.rps) ? String(h.rps) : ''],
      ['VERIFICATION', h.verificacao],
      ['COMPETENCE', formatDate(h.competencia)],
      ['SELLER', name(h.vendedor, h.vendedor_nome)],
      ['PAYMENT', h.pagamento],
      ['CANCELED_AT', formatDate(h.data_cancelamento)],
    ],
  };
  return (lists[viewKind.value] || []).filter(([, value]) => value);
});

const forecastLate = computed(
  () =>
    viewKind.value === 'orders' &&
    header.value.previsao &&
    !header.value.entrega &&
    isLate(header.value.previsao) &&
    !isOrderLocked(detail.value?.editor)
);

const items = computed(() => detail.value?.itens || []);
// "Editar OS" começa fechado (os itens vêm antes)
const editOpen = ref(false);
// "Liberar para separação": função e perfil (erpState), unidade liberada, OS em NEGOCIAÇÃO
const canRelease = computed(
  () =>
    viewKind.value === 'orders' &&
    erpState.canReleaseOrder &&
    erpState.orderCompanies.includes(view.value.company) &&
    isNegotiation(header.value.status)
);

const longTexts = computed(() =>
  [
    ['DEFECTS', header.value.defeitos],
    ['ACCESSORIES', header.value.acessorios],
    ['CANCEL_REASON', header.value.cancelamento],
    // chave de acesso de 44 dígitos em grupos de 4, como no DANFE
    [
      'ACCESS_KEY',
      String(header.value.chave || '').replace(/(\d{4})(?=\d)/g, '$1 '),
    ],
    ['NOTES', header.value.observacoes],
  ].filter(([, value]) => String(value || '').trim())
);

const accountId = computed(() => route.params.accountId);
const chatUrl = computed(() => {
  if (detail.value?.conversation_id)
    return frontendURL(
      `accounts/${accountId.value}/conversations/${detail.value.conversation_id}`
    );
  if (detail.value?.contact_id)
    return frontendURL(
      `accounts/${accountId.value}/contacts/${detail.value.contact_id}`
    );
  return '';
});

// ---- orçamento: gaveta de sempre ----
const edit = computed(() => detail.value?.edit || {});
// enviar e copiar pedem "Usa" na aba Orçamentos do perfil; editar pede também a gravação de orçamentos ligada
const canUseQuotes = computed(() => allows('erp_quotes', 'use'));
const canUseOrders = computed(() => allows('erp_orders', 'use'));
const canUseInvoices = computed(() => allows('erp_invoices', 'use'));
const canUseSales = computed(() => allows('erp_sales', 'use'));
const editBlocked = computed(() => {
  if (!canUseQuotes.value) return t('OUTSIDER_ERP.RECORDS.EDIT.NO_ACCESS');
  if (!erpState.quoteWriteEnabled)
    return t('OUTSIDER_ERP.RECORDS.EDIT.WRITE_OFF');
  if (edit.value.in_use_by)
    return t('OUTSIDER_ERP.RECORDS.EDIT.IN_USE', {
      name: edit.value.in_use_by,
    });
  if (!edit.value.allowed)
    return t('OUTSIDER_ERP.RECORDS.EDIT.STATUS', {
      status: header.value.status || '—',
    });
  return '';
});

const run = async (key, action) => {
  busy.value = key;
  try {
    await action();
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    busy.value = '';
  }
};

// orçamento feito no Mais Prático vira registro do chat na hora (para PDF, envio e cópia)
const ensureBudget = async () => {
  if (detail.value.budget_id) return { id: detail.value.budget_id };
  const { data } = await ErpAPI.importBudget({
    company: view.value.company,
    number: view.value.number,
    contact_id: detail.value.contact_id || undefined,
    name: client.value.nome || undefined,
  });
  detail.value = { ...detail.value, budget_id: data.budget.id };
  return data.budget;
};

const startEdit = () =>
  run('edit', async () => {
    const { data } = await ErpAPI.reviseBudget({
      company: view.value.company,
      number: view.value.number,
      contact_id: detail.value.contact_id || undefined,
    });
    detail.value = { ...detail.value, budget_id: data.budget.id };
    drawerRef.value?.open(data.budget, { focus: true });
  });

// Converter em OS: como no desktop, só orçamento em NEGOCIAÇÃO que ainda não virou OS nem pedido (a tela confere de novo)
const convertRef = ref(null);
const convertible = computed(
  () =>
    erpState.canConvertQuote &&
    erpState.orderCompanies.includes(view.value.company) &&
    isNegotiation(header.value.status) &&
    !(detail.value?.chain || []).some(node =>
      ['orders', 'sales'].includes(node.kind)
    )
);
const convert = () =>
  convertRef.value?.open({
    company: view.value.company,
    number: view.value.number,
    customerCode: header.value.cliente_codigo,
    customerName: client.value.nome,
    contactId: detail.value?.contact_id || null,
    conversationId: detail.value?.conversation_id || null,
  });

// PDF direto do ERP (sem criar registro); orçamento em edição no chat mostra a prévia dele
const showPdf = () =>
  run('pdf', async () => {
    if (detail.value.budget_id && detail.value.revising)
      pdfRef.value?.open(detail.value.budget_id);
    else
      pdfRef.value?.open(() =>
        ErpAPI.recordPdf(view.value.company, view.value.number)
      );
  });

// OS: o relatório montado na hora pelo servidor, no modelo do Tipo de Atendimento dela (ERP > Modelos de relatório);
// o botão diz o tipo quando ele tem modelo próprio
const reportLabel = computed(() => {
  const type = reportTypeName(header.value.atendimento);
  return type
    ? t('OUTSIDER_ERP.ORDER.REPORT_TYPE', { type })
    : t('OUTSIDER_ERP.ORDER.REPORT');
});
// OS: relatório com as fotos do checklist (o mesmo do kanban de KPI), montado na hora pelo servidor
const showReport = () =>
  run('report', () =>
    pdfRef.value?.open(() =>
      ErpAPI.serviceOrderReport(view.value.company, view.value.number)
    )
  );

// NF-e e NFS-e: aviso de nota que ainda não está na nuvem (Nextcloud)
const cloudStatus = ref('');
const loadCloud = async () => {
  const { kind, company, number } = view.value;
  cloudStatus.value = '';
  if (!CLOUD_KINDS.includes(kind)) return;
  const key = cloudKey(kind, company, number);
  const statuses = await fetchCloud(kind, [key]);
  if (cloudKey(view.value.kind, view.value.company, view.value.number) === key)
    cloudStatus.value = statuses[key] || '';
};
watch(
  () => [view.value.kind, view.value.company, view.value.number],
  loadCloud,
  { immediate: true }
);

// NF-e e NFS-e: o PDF oficial da nota, espelhado do Nextcloud (a prévia já tem o botão de baixar); depois de abrir, o
// aviso de nuvem é lido de novo (abrir já conta como verificação)
const showInvoice = () =>
  pdfRef.value
    ?.open(() =>
      ErpAPI.invoiceDocument(
        viewKind.value,
        view.value.company,
        view.value.number
      )
    )
    ?.finally?.(loadCloud);

// OS: o mesmo relatório, com a prévia e o envio ao cliente por WhatsApp ou e-mail (como o orçamento)
const sendDialogRef = ref(null);
const sendOrder = () =>
  sendDialogRef.value?.open({
    company: view.value.company,
    code: view.value.number,
    contactId: detail.value?.contact_id,
  });

// OS: agendar nas agendas conectadas (Microsoft/Google) com convidados e aviso no WhatsApp, ou só um texto no WhatsApp
const scheduleRef = ref(null);
const scheduleOrder = (mode = 'schedule') =>
  scheduleRef.value?.open(
    { company: view.value.company, code: view.value.number },
    mode
  );
// Agendar só até a OS ir para AGENDADO (o agendamento grava esse substatus); relatório e envio só com a OS concluída
// e o checklist respondido
const schedulable = computed(() =>
  orderSchedulable(header.value.status, header.value.substatus)
);
const { ready: reportReady, checking: reportChecking } = useOrderReady(() => ({
  company: view.value.company,
  code: view.value.number,
  concluded:
    viewKind.value === 'orders' &&
    orderConcluded(header.value.status, header.value.substatus),
}));
const scheduledLabel = row => {
  const [day, time] = String(row.start).split('T');
  const [, m, d] = day.split('-');
  return `${d}/${m}${row.all_day ? '' : ` ${time.slice(0, 5)}`}`;
};

// NF-e e NFS-e: a nota do Nextcloud enviada ao cliente por WhatsApp ou e-mail (como a OS)
const sendInvoice = () =>
  sendDialogRef.value?.open({
    kind: viewKind.value,
    company: view.value.company,
    code: view.value.number,
    contactId: detail.value?.contact_id,
    clientCode: header.value.cliente_codigo,
  });

const send = () =>
  run('send', async () => {
    const budget = await ensureBudget();
    drawerRef.value?.open(budget);
  });

const copy = () =>
  run('copy', async () => {
    const budget = await ensureBudget();
    const { data } = await ErpAPI.copyBudget(budget.id, {
      contact_id: detail.value.contact_id || undefined,
    });
    drawerRef.value?.open(data.budget, { focus: true });
  });

const orderLocked = computed(() => isOrderLocked(detail.value?.editor));

const LABEL =
  'text-[11px] font-medium uppercase tracking-wider text-n-slate-10';
</script>

<template>
  <aside
    class="flex flex-col w-full max-w-[32rem] shrink-0 bg-n-solid-2 border-n-weak"
    :class="
      floating
        ? 'fixed inset-y-0 right-0 z-50 border-l shadow-2xl'
        : 'fixed inset-y-0 right-0 z-40 border-l shadow-xl xl:shadow-none xl:static xl:z-auto xl:w-[30rem] xl:ml-4 xl:mb-4 xl:rounded-xl xl:border'
    "
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
            <h3 class="mb-0 text-lg font-semibold tabular-nums text-n-slate-12">
              {{ title }}
            </h3>
            <span
              v-if="header.status"
              class="px-2 py-0.5 text-[11px] font-medium rounded-full"
              :class="statusClass(header.status)"
            >
              {{ header.status }}
            </span>
          </div>
          <span class="text-[13px] truncate text-n-slate-11">
            {{
              [
                titleCase(client.nome) ||
                  (header.cliente_codigo && `#${header.cliente_codigo}`),
                place(client),
                companyName(view.company),
              ]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
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

      <div
        v-if="detail && viewKind === 'quotes'"
        class="flex flex-wrap items-center gap-2 mt-3"
      >
        <Button
          v-if="canUseQuotes"
          size="sm"
          icon="i-lucide-pencil"
          :label="t('OUTSIDER_ERP.RECORDS.EDIT.BUTTON')"
          :disabled="!!editBlocked"
          :title="editBlocked"
          :is-loading="busy === 'edit'"
          @click="startEdit"
        />
        <Button
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-file-text"
          :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.PDF')"
          :is-loading="busy === 'pdf'"
          @click="showPdf"
        />
        <Button
          v-if="canUseQuotes"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-send"
          :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.SEND')"
          :is-loading="busy === 'send'"
          @click="send"
        />
        <Button
          v-if="canUseQuotes"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-copy"
          :label="t('OUTSIDER_ERP.BUDGET.ACTIONS.COPY')"
          :is-loading="busy === 'copy'"
          @click="copy"
        />
        <Button
          v-if="convertible"
          size="sm"
          variant="faded"
          color="teal"
          icon="i-lucide-wrench"
          :label="t('OUTSIDER_ERP.ORDER_DRAFT.CONVERT.BUTTON')"
          data-erp-convert-quote
          @click="convert"
        />
      </div>
      <p
        v-if="
          detail &&
          viewKind === 'quotes' &&
          editBlocked &&
          canUseQuotes &&
          erpState.quoteWriteEnabled
        "
        class="flex items-center gap-1.5 mt-2 mb-0 text-xs text-n-slate-10"
      >
        <Icon icon="i-lucide-lock" class="size-3.5 shrink-0" />
        {{ editBlocked }}
      </p>
      <p
        v-if="detail && cloudStatus === 'missing'"
        class="flex items-center gap-1.5 mt-3 mb-0 text-xs font-medium text-n-amber-11"
        data-erp-panel-cloud-missing
      >
        <Icon icon="i-lucide-cloud-off" class="size-3.5 shrink-0" />
        {{ t('OUTSIDER_ERP.RECORDS.CLOUD.MISSING_HINT') }}
      </p>
      <div
        v-if="
          detail &&
          ['invoices', 'service_invoices'].includes(viewKind) &&
          erpState.nextcloudInvoices
        "
        class="flex flex-wrap items-center gap-2 mt-3"
      >
        <Button
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-file-text"
          :label="t('OUTSIDER_ERP.RECORDS.INVOICE.VIEW')"
          @click="showInvoice"
        />
        <Button
          v-if="canUseInvoices"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-send"
          :label="t('OUTSIDER_ERP.RECORDS.INVOICE.SEND.BUTTON')"
          @click="sendInvoice"
        />
      </div>
      <div
        v-if="detail && viewKind === 'orders'"
        class="flex flex-wrap items-center gap-2 mt-3"
      >
        <Button
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-file-text"
          :label="reportLabel"
          :is-loading="busy === 'report' || reportChecking"
          :disabled="!reportReady"
          @click="showReport"
        />
        <Button
          v-if="canUseOrders"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-send"
          :label="t('OUTSIDER_ERP.ORDER.SEND.BUTTON')"
          :disabled="!reportReady"
          @click="sendOrder"
        />
        <Button
          v-if="canUseOrders && schedulable"
          size="sm"
          color="blue"
          icon="i-lucide-calendar-plus"
          :label="t('OUTSIDER_ERP.ORDER.SCHEDULE_BUTTON')"
          data-erp-order-schedule
          @click="scheduleOrder('schedule')"
        />
        <Button
          v-if="canUseOrders"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-message-circle"
          :label="t('OUTSIDER_ERP.ORDER.MESSAGE_BUTTON')"
          data-erp-order-message
          @click="scheduleOrder('message')"
        />
        <button
          v-for="row in detail.schedules || []"
          :key="row.start"
          type="button"
          class="flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
          @click="scheduleOrder('schedule')"
        >
          <Icon icon="i-lucide-calendar-check" class="size-3.5" />
          {{ t('OUTSIDER_ERP.ORDER.SCHEDULED', { when: scheduledLabel(row) }) }}
        </button>
        <p
          v-if="!reportReady && !reportChecking"
          class="flex items-start w-full gap-1.5 mb-0 text-xs text-n-amber-11"
          data-erp-order-not-synced
        >
          <Icon
            icon="i-lucide-refresh-cw-off"
            class="size-3.5 shrink-0 mt-px"
          />
          {{ t('OUTSIDER_ERP.ORDER.NOT_SYNCED') }}
        </p>
      </div>
    </header>

    <div v-if="loading" class="flex items-center justify-center flex-1">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else-if="failure"
      class="flex flex-col items-center justify-center flex-1 gap-3 p-6 text-center"
    >
      <p class="mb-0 text-sm text-n-slate-11">{{ failure }}</p>
      <Button
        size="sm"
        variant="faded"
        color="slate"
        :label="t('OUTSIDER_ERP.CONTACT.RETRY')"
        @click="load"
      />
    </div>

    <div
      v-else
      class="flex flex-col flex-1 min-h-0 gap-5 px-5 pt-4 overflow-y-auto pb-24 md:pb-4"
    >
      <section v-if="detail.chain.length > 1" class="flex flex-col gap-2">
        <span :class="LABEL">{{ t('OUTSIDER_ERP.RECORDS.CHAIN.TITLE') }}</span>
        <ErpRecordChain :chain="detail.chain" @jump="openNode" />
      </section>

      <ErpSaleAttribution
        v-if="viewKind === 'sales'"
        :key="`${view.company}:${view.number}`"
        :company="view.company"
        :number="view.number"
        :can-edit="canUseSales"
        @changed="load"
      />

      <p
        v-if="viewKind === 'orders' && orderLocked"
        class="flex items-start gap-2 p-3 mb-0 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
      >
        <Icon icon="i-lucide-lock" class="mt-0.5 size-4 shrink-0" />
        {{ t('OUTSIDER_ERP.RECORDS.ORDERS.LOCKED', { status: header.status }) }}
      </p>
      <p
        v-else-if="forecastLate"
        class="flex items-center gap-2 p-3 mb-0 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11"
      >
        <Icon icon="i-lucide-alarm-clock" class="size-4 shrink-0" />
        {{
          t('OUTSIDER_ERP.RECORDS.ORDERS.LATE_SINCE', {
            date: formatDate(header.previsao),
          })
        }}
      </p>

      <dl class="grid grid-cols-2 mb-0 gap-x-5 gap-y-3 text-[13px]">
        <div v-for="[key, value] in facts" :key="key" class="min-w-0">
          <dt :class="LABEL" class="mb-0.5">
            {{ t(`OUTSIDER_ERP.RECORDS.FIELDS.${key}`) }}
          </dt>
          <dd
            class="mb-0 truncate"
            :class="
              key === 'FORECAST' && forecastLate
                ? 'text-n-ruby-11 font-medium'
                : 'text-n-slate-12'
            "
            :title="value"
          >
            {{ value }}
          </dd>
        </div>
        <!-- OUTSIDER: cliente do ERP ligado a vários contatos do chat: escolhe qual conversa abrir -->
        <div v-if="(detail.contacts || []).length > 1" class="min-w-0">
          <dt :class="LABEL" class="mb-0.5">
            {{ t('OUTSIDER_ERP.RECORDS.FIELDS.CHAT') }}
          </dt>
          <dd class="mb-0">
            <ErpClientChat :contacts="detail.contacts" />
          </dd>
        </div>
        <div v-else-if="chatUrl" class="min-w-0">
          <dt :class="LABEL" class="mb-0.5">
            {{ t('OUTSIDER_ERP.RECORDS.FIELDS.CHAT') }}
          </dt>
          <dd class="mb-0">
            <router-link
              :to="chatUrl"
              class="inline-flex items-center gap-1 font-medium text-n-brand hover:underline"
            >
              {{
                detail.conversation_id
                  ? t('OUTSIDER_ERP.RECORDS.OPEN_CHAT')
                  : t('OUTSIDER_ERP.RECORDS.OPEN_CONTACT')
              }}
              <Icon icon="i-lucide-arrow-up-right" class="size-3.5" />
            </router-link>
          </dd>
        </div>
      </dl>

      <section
        v-if="client.nome"
        class="flex flex-col gap-1 p-3 text-[13px] rounded-lg bg-n-alpha-1"
      >
        <span :class="LABEL">{{ t('OUTSIDER_ERP.RECORDS.CLIENT') }}</span>
        <span class="font-medium text-n-slate-12">
          {{ client.codigo }} · {{ titleCase(client.nome) }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{
            [
              client.documento,
              place(client),
              client.fone || client.celular,
              client.email,
            ]
              .filter(Boolean)
              .join(' · ')
          }}
        </span>
      </section>

      <ErpRecordItems
        :key="`${view.kind}:${view.company}:${view.number}`"
        :items="items"
        :header="header"
        :company="view.company"
        :number="view.number"
        :conference="viewKind === 'orders' ? detail.conference || null : null"
        :can-release="canRelease"
        @released="refresh"
      />

      <section
        v-for="[key, value] in longTexts"
        :key="key"
        class="flex flex-col gap-1"
      >
        <span :class="LABEL">{{
          t(`OUTSIDER_ERP.RECORDS.FIELDS.${key}`)
        }}</span>
        <p
          class="mb-0 text-[13px] whitespace-pre-line text-n-slate-12"
          :class="
            key === 'ACCESS_KEY' ? 'font-mono tabular-nums break-all' : ''
          "
        >
          {{ value }}
        </p>
      </section>

      <section
        v-if="
          viewKind === 'orders' &&
          erpState.ordersEnabled &&
          erpState.canEdit &&
          !orderLocked &&
          detail.editor
        "
        class="flex flex-col gap-2 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
        data-erp-order-edit
      >
        <!-- OUTSIDER: a edição fica fechada embaixo dos itens; abre num clique -->
        <button
          type="button"
          class="flex items-center justify-between w-full gap-2 px-3 py-2.5 text-[13px] text-left text-n-slate-11 hover:text-n-slate-12"
          :aria-expanded="editOpen"
          data-erp-order-edit-toggle
          @click="editOpen = !editOpen"
        >
          <span>
            <span class="font-medium text-n-slate-12">
              {{ t('OUTSIDER_ERP.RECORDS.ORDERS.EDIT') }}
            </span>
            · {{ t('OUTSIDER_ERP.RECORDS.ORDERS.EDIT_HINT') }}
          </span>
          <Icon
            :icon="editOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            class="size-4 shrink-0"
          />
        </button>
        <div v-if="editOpen" class="px-3 pb-3">
          <ErpOrderEditor
            :order="detail.editor"
            :options="detail.substatus_options || []"
            @updated="refresh"
          />
        </div>
      </section>

      <section v-if="detail.timeline.length" class="flex flex-col gap-2">
        <span :class="LABEL">{{
          t('OUTSIDER_ERP.RECORDS.TIMELINE.TITLE')
        }}</span>
        <ErpRecordTimeline :events="detail.timeline" />
      </section>
    </div>

    <ErpBudgetDrawer
      ref="drawerRef"
      :contact-id="detail?.contact_id || null"
      :conversation-id="detail?.conversation_id || null"
      @changed="refresh"
    />
    <ErpPdfDialog ref="pdfRef" />
    <ErpDocumentSendDialog ref="sendDialogRef" />
    <ErpOrderScheduleDialog ref="scheduleRef" @changed="load" />
    <ErpQuoteConvertDialog ref="convertRef" @converted="refresh" />
  </aside>
</template>
