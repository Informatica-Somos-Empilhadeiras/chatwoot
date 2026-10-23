<script setup>
// OUTSIDER: bolha de áudio com o player estilo WhatsApp (VoicePlayer.vue), com a cor da mensagem.
// Áudio de grupo traz quem enviou no texto. Escolhida em bubbleFor.js; a bolha original
// (bubbles/Audio.vue) fica intacta.
import { computed } from 'vue';
import BaseBubble from '../bubbles/Base.vue';
import VoicePlayer from './VoicePlayer.vue';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';
import { useMessageContext } from '../provider.js';

const { attachments, sender, orientation, content } = useMessageContext();

const attachment = computed(() => attachments.value[0]);
const senderHeader = computed(
  () => splitSenderHeader(content.value).header || ''
);
</script>

<template>
  <BaseBubble class="p-2" data-bubble-name="audio">
    <VoicePlayer
      :attachment="attachment"
      :sender="sender"
      :orientation="orientation"
      :header="senderHeader"
      class="skip-context-menu"
    />
  </BaseBubble>
</template>
