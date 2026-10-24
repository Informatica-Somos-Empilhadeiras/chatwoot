<script setup>
// OUTSIDER: aviso da Evolution traduzido (Entrega 21), no lugar do texto em inglês ou do "🚨" solto. A cor e o
// emoji dizem o tipo: erro (vermelho, ⛔), atenção (amarelo, ⚠️), tudo certo (verde, ✅) e aviso (azul, ℹ️). O
// tipo do problema fica em destaque no topo; embaixo, o que fazer. Ver dashboard/helper/outsider/evolutionNotice.js.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import MessageMeta from '../MessageMeta.vue';
import { useMessageContext } from '../provider.js';
import { evolutionNoticeOf } from 'dashboard/helper/outsider/evolutionNotice';

const LEVELS = {
  error: {
    emoji: '⛔',
    card: 'bg-n-ruby-3 outline-n-ruby-7',
    badge: 'bg-n-ruby-9 text-white',
    title: 'text-n-ruby-12',
  },
  warning: {
    emoji: '⚠️',
    card: 'bg-n-amber-3 outline-n-amber-7',
    badge: 'bg-n-amber-9 text-n-amber-12',
    title: 'text-n-amber-12',
  },
  success: {
    emoji: '✅',
    card: 'bg-n-teal-3 outline-n-teal-7',
    badge: 'bg-n-teal-9 text-white',
    title: 'text-n-teal-12',
  },
  info: {
    emoji: 'ℹ️',
    card: 'bg-n-blue-3 outline-n-blue-7',
    badge: 'bg-n-blue-9 text-white',
    title: 'text-n-blue-12',
  },
};

const { content, attachments } = useMessageContext();
const { t } = useI18n();

const notice = computed(() =>
  evolutionNoticeOf({ content: content.value, attachments: attachments.value })
);
const look = computed(() => LEVELS[notice.value?.level] || LEVELS.info);

const stateLabel = computed(() => {
  const key = `OUTSIDER_WHATSAPP.NOTICES.STATES.${notice.value.state.toUpperCase()}`;
  return t(key) === key ? notice.value.state : t(key);
});

const params = computed(() => ({
  inbox: notice.value.inbox,
  state: stateLabel.value,
  count: notice.value.count,
}));

const detailText = computed(() => {
  if (!notice.value.detail) return '';
  return notice.value.detailKey
    ? t(`OUTSIDER_WHATSAPP.NOTICES.DETAILS.${notice.value.detailKey}`)
    : notice.value.detail;
});
</script>

<template>
  <div
    class="flex gap-3 p-3 text-sm max-w-md rounded-xl outline outline-1 -outline-offset-1 text-n-slate-12"
    :class="look.card"
    :data-notice="notice.type"
  >
    <span class="text-2xl leading-none shrink-0" aria-hidden="true">
      {{ look.emoji }}
    </span>
    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="px-1.5 py-0.5 text-[0.6875rem] font-semibold tracking-wide uppercase rounded"
          :class="look.badge"
        >
          {{
            t(`OUTSIDER_WHATSAPP.NOTICES.LEVELS.${notice.level.toUpperCase()}`)
          }}
        </span>
        <span class="font-semibold" :class="look.title">
          {{ t(`OUTSIDER_WHATSAPP.NOTICES.${notice.type}.TITLE`, params) }}
        </span>
      </div>
      <p class="mb-0 text-n-slate-12">
        {{ t(`OUTSIDER_WHATSAPP.NOTICES.${notice.type}.TEXT`, params) }}
      </p>
      <p
        v-if="detailText"
        class="flex flex-wrap gap-1 mb-0 text-xs text-n-slate-11"
      >
        <span class="font-medium">
          {{ t('OUTSIDER_WHATSAPP.NOTICES.DETAIL') }}
        </span>
        <span :class="{ 'font-mono break-all': !notice.detailKey }">
          {{ detailText }}
        </span>
      </p>
      <MessageMeta class="justify-end mt-1 text-n-slate-11" />
    </div>
  </div>
</template>
