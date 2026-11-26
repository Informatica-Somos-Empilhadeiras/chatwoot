<script setup>
// OUTSIDER: uma ordem de serviço do ERP (espelho). Fechada mostra o essencial; aberta mostra os detalhes, o relatório
// com as fotos do checklist (PDF, ErpPdfDialog), o envio dele ao cliente (ErpDocumentSendDialog, para quem "Usa" as OS) e,
// para quem pode editar (escrita ligada + perfil "Usa"), os controles de edição (ErpOrderEditor). O cartão só exibe; a
// edição e a gravação ficam no editor.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpOrderEditor from './ErpOrderEditor.vue';
import ErpPdfDialog from '../budgets/ErpPdfDialog.vue';
import ErpDocumentSendDialog from './ErpDocumentSendDialog.vue';
import ErpOrderScheduleDialog from './ErpOrderScheduleDialog.vue';
import { useOrderReady } from './orderReady';
import { allows } from '../../access/accessStore';
import {
  erpState,
  formatDate,
  dotClass,
  substatusClass,
  reportTypeName,
  companyName,
  orderConcluded,
  orderSchedulable,
} from '../erpStore';

const props = defineProps({
  order: { type: Object, required: true },
  options: { type: Array, default: () => [] },
  conversationId: { type: [Number, String], default: null },
  startOpen: { type: Boolean, default: false },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();
const open = ref(props.startOpen);
const pdfRef = ref(null);
const sendRef = ref(null);
const canSend = computed(() => allows('erp_orders', 'use'));
// OUTSIDER: Agendar tem linha própria no perfil de acesso (Agendar OS)
const canSchedule = computed(() => allows('erp_order_schedule', 'use'));

const openSend = () =>
  sendRef.value?.open({
    company: props.order.Empresa,
    code: props.order.CodigoOS,
    conversationId: props.conversationId,
    clientCode: props.order.CodigoCliente,
  });

const openReport = () =>
  pdfRef.value?.open(() =>
    ErpAPI.serviceOrderReport(props.order.Empresa, props.order.CodigoOS)
  );

// agendar nas agendas conectadas (Microsoft/Google) ou só mandar um texto no WhatsApp
const scheduleRef = ref(null);
const openSchedule = mode =>
  scheduleRef.value?.open(
    { company: props.order.Empresa, code: props.order.CodigoOS },
    mode
  );

// Agendar fica à vista no cartão (verde) até a OS ir para o substatus AGENDADO, que o próprio agendamento grava
const schedulable = computed(() =>
  orderSchedulable(props.order.Situacao, props.order.SubStatus)
);
const onScheduled = result => {
  if (result?.substatus?.ok)
    emit('updated', { ...props.order, SubStatus: result.substatus.value });
};

// Emitir relatório e Enviar: só com a OS concluída e o checklist já respondido (sincronizado)
const { ready: reportReady, checking: reportChecking } = useOrderReady(
  () => ({
    company: props.order.Empresa,
    code: props.order.CodigoOS,
    concluded: orderConcluded(
      props.order.Situacao,
      props.order.SubStatus,
      props.order.StatusKanban
    ),
  }),
  () => open.value
);

const late = computed(() => Number(props.order.DiasAtraso) > 0);
const reportLabel = computed(() => {
  const type = reportTypeName(props.order.TipoAtendimento);
  return type
    ? t('OUTSIDER_ERP.ORDER.REPORT_TYPE', { type })
    : t('OUTSIDER_ERP.ORDER.REPORT');
});

const details = computed(() =>
  [
    ['SITUATION', props.order.Situacao],
    ['SERVICE', props.order.TipoAtendimento],
    [
      'KIND',
      [props.order.Classe, props.order.TipoOS].filter(Boolean).join(' · '),
    ],
    ['SERIAL', props.order.NSerie],
    ['MACHINE_STATUS', props.order.StatusMaquina],
    ['OWNERSHIP', props.order.PropriedadeMaquina],
    ['SELLER', props.order.NomeVendedor],
    ['ATTENDANT', props.order.NomeAtendente],
    ['DELIVERY', formatDate(props.order.DataEntrega)],
    ['LAST_STATUS', formatDate(props.order.DtUltimoStatus)],
    [
      'ITEMS',
      t('OUTSIDER_ERP.ORDER.ITEMS_VALUE', {
        products: props.order.QtdProduto || 0,
        services: props.order.QtdServico || 0,
      }),
    ],
  ].filter(([, value]) => value)
);
</script>

<template>
  <article
    class="flex flex-col gap-2 p-3 text-sm border rounded-xl border-n-weak bg-n-solid-1"
  >
    <button
      type="button"
      class="flex flex-col gap-1.5 text-left"
      :aria-expanded="open"
      @click="open = !open"
    >
      <div class="flex items-center justify-between w-full gap-2">
        <span
          class="flex items-center gap-1.5 font-medium whitespace-nowrap text-n-slate-12"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :class="dotClass(order.Cor)"
          />
          {{ t('OUTSIDER_ERP.ORDER.CODE', { code: order.CodigoOS }) }}
          <span class="text-xs font-normal text-n-slate-10">
            {{ companyName(order.Empresa) }}
          </span>
        </span>
        <span
          class="min-w-0 px-2 py-0.5 text-xs rounded-full truncate"
          :class="substatusClass(order.SubStatus)"
          :title="order.SubStatus"
        >
          {{ order.SubStatus || t('OUTSIDER_ERP.ORDER.NO_SUBSTATUS') }}
        </span>
      </div>
      <span
        v-if="order.DescricaoMaquina"
        class="flex items-center gap-1.5 text-n-slate-11"
      >
        <Icon icon="i-lucide-forklift" class="size-3.5 shrink-0" />
        <span class="truncate">{{ order.DescricaoMaquina }}</span>
      </span>
      <span
        class="flex flex-wrap items-center text-xs gap-x-3 gap-y-1 text-n-slate-11"
      >
        <span v-if="order.TipoAtendimento">{{ order.TipoAtendimento }}</span>
        <span>
          {{
            t('OUTSIDER_ERP.ORDER.ENTRY', {
              date: formatDate(order.DataEntrada),
            })
          }}
        </span>
        <span
          v-if="order.DataPrevisao"
          :class="late ? 'text-n-ruby-11 font-medium' : ''"
        >
          {{
            late
              ? t('OUTSIDER_ERP.ORDER.LATE', {
                  date: formatDate(order.DataPrevisao),
                  days: order.DiasAtraso,
                })
              : t('OUTSIDER_ERP.ORDER.FORECAST', {
                  date: formatDate(order.DataPrevisao),
                })
          }}
        </span>
        <span v-if="order.NomeTecnico" class="flex items-center gap-1">
          <Icon icon="i-lucide-wrench" class="size-3" />
          {{ order.NomeTecnico }}
        </span>
      </span>
    </button>

    <div v-if="canSchedule && schedulable" class="flex">
      <Button
        size="sm"
        color="blue"
        icon="i-lucide-calendar-plus"
        :label="t('OUTSIDER_ERP.ORDER.SCHEDULE_BUTTON')"
        data-erp-card-schedule
        @click="openSchedule('schedule')"
      />
    </div>

    <div v-if="open" class="flex flex-col gap-3 pt-2 border-t border-n-weak">
      <div class="flex flex-wrap gap-2">
        <Button
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-file-text"
          :label="reportLabel"
          :disabled="!reportReady"
          :is-loading="reportChecking"
          data-erp-card-report
          @click="openReport"
        />
        <Button
          v-if="canSend"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-send"
          :label="t('OUTSIDER_ERP.ORDER.SEND.BUTTON')"
          :disabled="!reportReady"
          data-erp-card-send
          @click="openSend"
        />
        <ErpPdfDialog ref="pdfRef" />
        <Button
          v-if="canSend"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-message-circle"
          :label="t('OUTSIDER_ERP.ORDER.MESSAGE_BUTTON')"
          @click="openSchedule('message')"
        />
        <ErpDocumentSendDialog ref="sendRef" />
      </div>
      <p
        v-if="!reportReady && !reportChecking"
        class="flex items-start gap-1.5 mb-0 text-xs text-n-amber-11"
        data-erp-card-not-synced
      >
        <Icon icon="i-lucide-refresh-cw-off" class="size-3.5 shrink-0 mt-px" />
        {{ t('OUTSIDER_ERP.ORDER.NOT_SYNCED') }}
      </p>
      <p v-if="order.Nome" class="mb-0 text-xs font-medium text-n-slate-12">
        {{ order.Nome }}
        <span class="font-normal text-n-slate-10">
          ·
          {{
            t('OUTSIDER_ERP.ORDER.CUSTOMER_CODE', { code: order.CodigoCliente })
          }}
          <template v-if="order.Cidade">
            · {{ order.Cidade }}/{{ order.UF }}
          </template>
        </span>
      </p>
      <dl class="grid grid-cols-2 gap-x-3 gap-y-1.5 text-xs mb-0">
        <template v-for="[key, value] in details" :key="key">
          <div class="flex flex-col min-w-0">
            <dt class="text-n-slate-10">
              {{ t(`OUTSIDER_ERP.ORDER.DETAILS.${key}`) }}
            </dt>
            <dd class="mb-0 truncate text-n-slate-12" :title="value">
              {{ value }}
            </dd>
          </div>
        </template>
      </dl>
      <div v-if="order.Observacoes" class="flex flex-col gap-0.5 text-xs">
        <span class="text-n-slate-10">
          {{ t('OUTSIDER_ERP.FIELDS.OBSERVACOES') }}
        </span>
        <p class="mb-0 whitespace-pre-line text-n-slate-12">
          {{ order.Observacoes }}
        </p>
      </div>

      <ErpOrderEditor
        v-if="erpState.canEdit"
        :order="order"
        :options="options"
        :conversation-id="conversationId"
        @updated="emit('updated', $event)"
      />
      <template v-else>
        <div v-if="order.Defeitos" class="flex flex-col gap-0.5 text-xs">
          <span class="text-n-slate-10">{{
            t('OUTSIDER_ERP.FIELDS.DEFEITOS')
          }}</span>
          <p class="mb-0 whitespace-pre-line text-n-slate-12">
            {{ order.Defeitos }}
          </p>
        </div>
        <p v-if="erpState.writeEnabled" class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.ORDER.VIEW_ONLY') }}
        </p>
      </template>
    </div>
    <ErpOrderScheduleDialog ref="scheduleRef" @changed="onScheduled" />
  </article>
</template>
