<script setup>
// OUTSIDER: linha do tempo do registro (Outsider::Erp::Records::Timeline): o que aconteceu no ERP com o orçamento, as
// OS, os pedidos e as notas da corrente, e o que foi feito pelo chat (criação, desconto liberado, edições, envios). Mais novo em
// cima; cada evento com bolinha e linha, como o histórico da jornada do CRM.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { displayNumber } from './recordsConfig';

const props = defineProps({
  events: { type: Array, default: () => [] },
});

const { t } = useI18n();

const STYLE = {
  created: ['i-lucide-file-plus-2', 'bg-n-slate-3 text-n-slate-11'],
  status: ['i-lucide-flag', 'bg-n-amber-3 text-n-amber-11'],
  authorized: ['i-lucide-badge-check', 'bg-n-teal-3 text-n-teal-11'],
  delivered: ['i-lucide-package-check', 'bg-n-teal-3 text-n-teal-11'],
  invoiced: ['i-lucide-receipt-text', 'bg-n-blue-3 text-n-blue-11'],
  chat_created: ['i-lucide-message-square-plus', 'bg-n-brand/15 text-n-brand'],
  chat_approved: ['i-lucide-badge-percent', 'bg-n-teal-3 text-n-teal-11'],
  chat_edited: ['i-lucide-pencil', 'bg-n-blue-3 text-n-blue-11'],
  sent: ['i-lucide-send', 'bg-n-brand/15 text-n-brand'],
};

const when = value => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const options = {
    timeZone: 'America/Sao_Paulo',
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  };
  const day = date.toLocaleDateString('pt-BR', options);
  // o ERP guarda só o dia (meia-noite de Brasília): sem hora
  const time = date.toLocaleTimeString('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    hour: '2-digit',
    minute: '2-digit',
  });
  return time === '00:00' ? day : `${day} ${time}`;
};

const record = event =>
  event.kind
    ? `${t(`OUTSIDER_ERP.RECORDS.CHAIN.${event.kind.toUpperCase()}`)} ${displayNumber(event)}`
    : '';

const text = event => {
  const values = {
    record: record(event),
    name: event.name || '—',
    status: event.status || '',
    channel: event.channel
      ? t(
          `OUTSIDER_ERP.RECORDS.TIMELINE.CHANNEL_${event.channel.toUpperCase()}`
        )
      : '',
    to: (event.to || []).filter(Boolean).join(', '),
  };
  const key =
    event.type === 'sent' && !values.to
      ? 'SENT_NO_TO'
      : event.type.toUpperCase();
  return t(`OUTSIDER_ERP.RECORDS.TIMELINE.${key}`, values);
};

const list = computed(() => [...props.events].reverse());
</script>

<template>
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
        :class="(STYLE[event.type] || STYLE.created)[1]"
      >
        <Icon
          :icon="(STYLE[event.type] || STYLE.created)[0]"
          class="size-3.5"
        />
      </span>
      <div class="flex flex-col min-w-0 pt-0.5">
        <span class="text-[13px] leading-snug text-n-slate-12">
          {{ text(event) }}
        </span>
        <span class="text-[11px] tabular-nums text-n-slate-10">
          {{ when(event.at) }}
          <template v-if="event.type === 'sent' && event.status === 'failed'">
            · {{ t('OUTSIDER_ERP.RECORDS.TIMELINE.FAILED') }}
          </template>
        </span>
      </div>
    </li>
  </ol>
</template>
