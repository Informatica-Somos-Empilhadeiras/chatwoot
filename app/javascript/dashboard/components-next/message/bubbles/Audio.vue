<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
// OUTSIDER: player de áudio estilo WhatsApp no lugar do AudioChip
import VoicePlayer from '../outsider/VoicePlayer.vue';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';
import { useMessageContext } from '../provider.js';

const { attachments, sender, orientation, content } = useMessageContext();

const attachment = computed(() => {
  return attachments.value[0];
});

// OUTSIDER: áudio de grupo traz quem enviou no texto
const senderHeader = computed(
  () => splitSenderHeader(content.value).header || ''
);
</script>

<template>
  <!-- OUTSIDER: bolha com a cor da mensagem, como no WhatsApp -->
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
