<script setup>
// OUTSIDER: bolha de áudio com o player estilo WhatsApp (VoicePlayer.vue), com a cor da mensagem.
// Áudio de grupo traz quem enviou no texto. Escolhida em bubbleFor.js; a bolha original
// (bubbles/Audio.vue) fica intacta. "Transcrever" faz a transcrição no navegador e guarda no anexo
// (api/outsider/transcriptions.js); o texto chega para todos pelo message.updated.
import { computed } from 'vue';
import TranscriptionsAPI from 'dashboard/api/outsider/transcriptions';
import BaseBubble from '../bubbles/Base.vue';
import VoicePlayer from './VoicePlayer.vue';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';
import { useMessageContext } from '../provider.js';

const { attachments, sender, orientation, content } = useMessageContext();

const attachment = computed(() => attachments.value[0]);
const senderHeader = computed(
  () => splitSenderHeader(content.value).header || ''
);

const saveTranscript = (text, result) =>
  TranscriptionsAPI.save(attachment.value.id, {
    text,
    engine: 'navegador',
    model: result?.model || result?.size || '',
    language: 'pt',
    duration: result?.duration || 0,
  });
</script>

<template>
  <BaseBubble class="p-2" data-bubble-name="audio">
    <VoicePlayer
      :attachment="attachment"
      :sender="sender"
      :orientation="orientation"
      :header="senderHeader"
      :transcriber="saveTranscript"
      :transcribe-url="TranscriptionsAPI.audioUrl(attachment.id)"
      class="skip-context-menu"
    />
  </BaseBubble>
</template>
