<script setup>
// OUTSIDER: barra da caixa de resposta no jeito do WhatsApp. O ReplyBox.vue importa este arquivo no
// lugar da ReplyBottomPanel.vue, que continua original e é desenhada aqui dentro com tudo o que o
// ReplyBox passa. Em volta dela:
// - à esquerda, o clipe com o menu do WhatsApp (ComposerAttachMenu.vue); o clipe original fica
//   escondido, mas é ele que recebe os arquivos (e o arrastar e soltar continua igual);
// - os botões originais (emoji, assinatura, modelos...) ficam só com o ícone, redondos;
// - à direita, microfone com a caixa vazia e o botão de enviar quando há texto, no lugar do
//   "Enviar (CTRL + ↵)". Gravando, a barra some e o gravador (VoiceRecorder.vue) assume.
// Os ajustes visuais na barra original usam as classes dela (left-wrap, right-wrap, file-uploads);
// se uma atualização do Chatwoot mudar essas classes, a barra volta a aparecer como a original.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ReplyBottomPanel from '../ReplyBottomPanel.vue';
import ComposerAttachMenu from './ComposerAttachMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineOptions({ inheritAttrs: false });

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
  conversationId: { type: Number, default: null },
  isNote: { type: Boolean, default: false },
  isOnPrivateNote: { type: Boolean, default: false },
  isEditorDisabled: { type: Boolean, default: false },
  isRecordingAudio: { type: Boolean, default: false },
  isSendDisabled: { type: Boolean, default: false },
  showFileUpload: { type: Boolean, default: false },
  showAudioRecorder: { type: Boolean, default: false },
  toggleAudioRecorder: { type: Function, default: () => {} },
  onSend: { type: Function, default: () => {} },
  sendButtonText: { type: String, default: '' },
});

const EVOLUTION_WEBHOOK = /\/chatwoot\/webhook\//;
const NO_AUDIO_CHANNELS = ['Channel::Line', 'Channel::Tiktok'];

const { t } = useI18n();
const rootRef = ref(null);
const panelRef = ref(null);

// mesma regra do clipe original (ReplyBottomPanel: showAttachButton)
const canAttach = computed(
  () => !props.isEditorDisabled && (props.showFileUpload || props.isNote)
);
const canShareWhatsapp = computed(
  () =>
    !props.isOnPrivateNote &&
    !props.isEditorDisabled &&
    EVOLUTION_WEBHOOK.test(props.inbox?.webhook_url || '')
);
// mesma regra do microfone original (ReplyBottomPanel: showAudioRecorderButton)
const canRecord = computed(
  () =>
    props.showAudioRecorder &&
    !props.isEditorDisabled &&
    !NO_AUDIO_CHANNELS.includes(props.inbox?.channel_type)
);
const showMic = computed(() => canRecord.value && props.isSendDisabled);

// Abre o seletor de arquivos do clipe original. "media" limita a fotos e vídeos só desta vez.
const pickFiles = kind => {
  const input = panelRef.value?.$el?.querySelector?.('input[type="file"]');
  if (!input) return;
  if (kind === 'media') {
    const original = input.getAttribute('accept');
    const restore = () => {
      if (original === null) input.removeAttribute('accept');
      else input.setAttribute('accept', original);
    };
    input.setAttribute('accept', 'image/*,video/*');
    input.addEventListener('change', restore, { once: true });
    window.addEventListener('focus', restore, { once: true });
  }
  input.click();
};

// Respostas prontas do Chatwoot abrem quando se digita "/" no começo da caixa
const openQuickReplies = () => {
  const editor = rootRef.value
    ?.closest('.reply-box')
    ?.querySelector('.ProseMirror[contenteditable="true"]');
  if (!editor) return;
  editor.focus();
  document.execCommand('insertText', false, '/');
};
</script>

<template>
  <div
    v-show="!isRecordingAudio"
    ref="rootRef"
    class="flex items-center gap-1 px-2 pt-1 pb-2"
    data-composer-bar
  >
    <ComposerAttachMenu
      :conversation-id="conversationId"
      :can-attach="canAttach"
      :can-share-whatsapp="canShareWhatsapp"
      :can-quick-reply="!isEditorDisabled"
      @pick-files="pickFiles"
      @quick-reply="openQuickReplies"
    />
    <ReplyBottomPanel
      ref="panelRef"
      v-bind="$attrs"
      class="outsider-composer-panel"
      :inbox="inbox"
      :conversation-id="conversationId"
      :is-note="isNote"
      :is-on-private-note="isOnPrivateNote"
      :is-editor-disabled="isEditorDisabled"
      :is-recording-audio="isRecordingAudio"
      :is-send-disabled="isSendDisabled"
      :show-file-upload="showFileUpload"
      :show-audio-recorder="false"
      :toggle-audio-recorder="toggleAudioRecorder"
      :on-send="onSend"
      :send-button-text="sendButtonText"
    />
    <button
      v-if="showMic"
      v-tooltip.top-end="t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
      type="button"
      class="grid text-white rounded-full shadow-sm size-10 shrink-0 place-content-center bg-[#00a884] hover:bg-[#008f6f]"
      :aria-label="t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
      data-composer-mic
      @click="toggleAudioRecorder"
    >
      <Icon icon="i-ph-microphone-fill" class="size-5" />
    </button>
    <button
      v-else
      v-tooltip.top-end="sendButtonText"
      type="button"
      class="grid text-white rounded-full shadow-sm size-10 shrink-0 place-content-center disabled:opacity-40 disabled:cursor-not-allowed"
      :class="
        isNote
          ? 'bg-n-amber-9 enabled:hover:bg-n-amber-10'
          : 'bg-[#00a884] enabled:hover:bg-[#008f6f]'
      "
      :aria-label="sendButtonText"
      :disabled="isSendDisabled"
      data-composer-send
      @click="onSend"
    >
      <Icon icon="i-ph-paper-plane-right-fill" class="size-5" />
    </button>
  </div>
</template>

<style lang="scss" scoped>
// a barra original sem o próprio espaçamento, só com ícones redondos e sem o "Enviar"
.outsider-composer-panel {
  @apply flex-1 min-w-0 p-0 #{!important};

  :deep(.left-wrap) {
    @apply flex-wrap gap-1;
  }

  :deep(.left-wrap button:not([aria-pressed='true'])) {
    @apply size-9 px-0 justify-center rounded-full bg-transparent text-n-slate-11 #{!important};

    &:hover {
      @apply bg-n-alpha-2 text-n-slate-12 #{!important};
    }
  }

  :deep(.left-wrap button[aria-pressed='true']) {
    @apply size-9 px-0 justify-center rounded-full #{!important};
  }

  :deep(.left-wrap button [class*='i-']) {
    @apply size-5 #{!important};
  }

  // o clipe original some da vista, mas segue recebendo os arquivos
  :deep(.file-uploads) {
    @apply absolute size-px overflow-hidden opacity-0 pointer-events-none #{!important};
  }

  :deep(.right-wrap) {
    @apply hidden #{!important};
  }
}
</style>
