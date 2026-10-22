<script setup>
// OUTSIDER: histórico de envios da proposta, do mais novo ao mais antigo: canal, contato, quem enviou,
// versão do PDF (muda quando a proposta é alterada depois de enviada), situação e os links para o
// arquivo que foi para o cliente e para a conversa.
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { formatDateTime } from '../../helpers';
import { crmState } from '../../crmStore';

defineProps({
  sends: { type: Array, required: true },
});

const { t } = useI18n();
const router = useRouter();

const CHANNEL_ICONS = {
  whatsapp: 'i-lucide-message-circle',
  email: 'i-lucide-mail',
};

const STATE_COLORS = {
  pending: 'bg-n-amber-3 text-n-amber-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
  sent: 'bg-n-slate-3 text-n-slate-11',
  delivered: 'bg-n-teal-3 text-n-teal-11',
  read: 'bg-n-blue-3 text-n-blue-11',
};

// situação da mensagem na conversa (quando o canal informa) ou do envio pelo servidor de e-mail
const state = send => {
  if (send.status === 'pending' || send.status === 'failed') return send.status;
  if (send.message_status === 'failed') return 'failed';
  if (['delivered', 'read'].includes(send.message_status))
    return send.message_status;
  return 'sent';
};

const openConversation = send =>
  router.push(
    frontendURL(
      `accounts/${crmState.accountId}/conversations/${send.conversation_display_id}`
    )
  );
</script>

<template>
  <ul
    class="flex flex-col mb-0 divide-y rounded-xl divide-n-weak outline outline-1 -outline-offset-1 outline-n-weak"
  >
    <li
      v-for="send in sends"
      :key="send.id"
      class="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 text-sm"
    >
      <Icon
        :icon="CHANNEL_ICONS[send.channel]"
        class="size-4 shrink-0 text-n-slate-11"
      />
      <span class="flex flex-col flex-1 min-w-[12rem]">
        <span class="truncate text-n-slate-12">
          {{ send.contact_name || send.recipient }}
          <span class="text-n-slate-11">· {{ send.recipient }}</span>
        </span>
        <span class="text-xs text-n-slate-11">
          {{
            t('OUTSIDER_CRM.PROPOSALS.SEND.HISTORY.LINE', {
              date: formatDateTime(send.created_at, t),
              name: send.user?.name || '—',
              version: send.version || 1,
            })
          }}
        </span>
        <span v-if="send.error" class="text-xs text-n-ruby-11">
          {{ send.error }}
        </span>
      </span>
      <span
        class="px-2 py-0.5 text-xs rounded-md whitespace-nowrap"
        :class="STATE_COLORS[state(send)]"
      >
        {{
          t(`OUTSIDER_CRM.PROPOSALS.SEND.STATE.${state(send).toUpperCase()}`)
        }}
      </span>
      <a
        v-if="send.file_url"
        :href="send.file_url"
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center gap-1 text-xs text-n-blue-11 hover:underline"
      >
        <Icon icon="i-lucide-file-text" class="size-3.5" />
        {{ t('OUTSIDER_CRM.PROPOSALS.SEND.HISTORY.FILE') }}
      </a>
      <button
        v-if="send.conversation_display_id"
        type="button"
        class="flex items-center gap-1 text-xs text-n-blue-11 hover:underline"
        @click="openConversation(send)"
      >
        <Icon icon="i-lucide-messages-square" class="size-3.5" />
        {{ t('OUTSIDER_CRM.PROPOSALS.SEND.HISTORY.CONVERSATION') }}
      </button>
    </li>
  </ul>
</template>
