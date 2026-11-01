<script setup>
// OUTSIDER: barra do modo seleção, no lugar da caixa de resposta (como no WhatsApp):
// "X  3 selecionadas   Copiar  Encaminhar". Encaminhar usa o mesmo modal e a mesma rota do
// encaminhar de uma mensagem (FowardMessageModal.vue), uma mensagem por vez, na ordem.
import { computed, watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';
import {
  selection,
  selectedMessages,
  stopSelection,
} from 'dashboard/composables/outsider/useMessageSelection';

const props = defineProps({
  conversationId: { type: Number, default: null },
});

const { t } = useI18n();

const isOpen = computed(
  () => selection.active && selection.conversationId === props.conversationId
);
const count = computed(() => selection.ids.length);
const forwardable = computed(() =>
  selectedMessages.value.filter(message => message.canForward)
);

// trocar de conversa sai do modo seleção
watch(
  () => props.conversationId,
  () => {
    if (selection.active) stopSelection();
  }
);

const forward = () => {
  if (!forwardable.value.length) {
    useAlert(t('OUTSIDER_WHATSAPP.LOOK.SELECT.NOT_FORWARDABLE'));
    return;
  }
  emitter.emit('CMD_OPEN_CUSTOM_FORWARD', {
    inboxId: forwardable.value[0].inboxId,
    messages: forwardable.value.map(({ content, attachments }) => ({
      content,
      attachments,
    })),
    skipped: count.value - forwardable.value.length,
  });
};

// "[13:59, 01/11/2026] Nome: texto", como o WhatsApp copia várias mensagens
const copy = async () => {
  const lines = selectedMessages.value.map(message => {
    const { header, body } = splitSenderHeader(message.content);
    const name = header?.split(/\s+-\s+/)[1] || header || message.senderName;
    const stamp = messageTimestamp(message.createdAt, 'HH:mm, dd/MM/yyyy');
    const files = message.attachments.length
      ? ` [${message.attachments.map(file => file.dataUrl || file.data_url).join(' ')}]`
      : '';
    return `[${stamp}] ${name ? `${name}: ` : ''}${body}${files}`.trim();
  });
  await copyTextToClipboard(lines.join('\n'));
  useAlert(t('OUTSIDER_WHATSAPP.LOOK.SELECT.COPIED'));
};

const onForwardDone = () => stopSelection();
emitter.on('OUTSIDER_FORWARD_DONE', onForwardDone);
onUnmounted(() => {
  emitter.off('OUTSIDER_FORWARD_DONE', onForwardDone);
  if (selection.active) stopSelection();
});
</script>

<template>
  <transition
    enter-active-class="transition duration-150 ease-out"
    enter-from-class="translate-y-2 opacity-0"
    leave-active-class="transition duration-100 ease-in"
    leave-to-class="opacity-0"
  >
    <div
      v-if="isOpen"
      class="absolute inset-0 z-30 flex items-center gap-3 px-4 bg-n-surface-1 border-t border-n-weak"
      data-selection-bar
    >
      <button
        v-tooltip.top="t('OUTSIDER_WHATSAPP.LOOK.SELECT.CANCEL')"
        type="button"
        class="grid rounded-full size-9 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
        @click="stopSelection"
      >
        <span class="i-lucide-x size-5" />
      </button>
      <div class="flex flex-col flex-1 min-w-0">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t('OUTSIDER_WHATSAPP.LOOK.SELECT.COUNT', { count }, count) }}
        </span>
        <span class="text-xs truncate text-n-slate-10">
          {{ t('OUTSIDER_WHATSAPP.LOOK.SELECT.HINT') }}
        </span>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-2 px-3 h-9 text-sm font-medium rounded-full text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40"
        :disabled="!count"
        @click="copy"
      >
        <span class="i-lucide-copy size-4" />
        {{ t('OUTSIDER_WHATSAPP.LOOK.SELECT.COPY') }}
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-2 px-4 h-9 text-sm font-semibold rounded-full text-white bg-[#1DAA61] hover:bg-[#178f51] disabled:opacity-40"
        :disabled="!count"
        data-selection-forward
        @click="forward"
      >
        <span class="i-lucide-forward size-4" />
        {{ t('OUTSIDER_WHATSAPP.LOOK.SELECT.FORWARD') }}
      </button>
    </div>
  </transition>
</template>
