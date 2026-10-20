<script setup>
// OUTSIDER: em volta da caixa de resposta (MessagesView.vue). No modo "Nota interna CRM" mostra o
// editor de nota do CRM; fora dele, a caixa de resposta de sempre, sem nenhuma mudança.
import { computed } from 'vue';
import CrmNoteComposer from './CrmNoteComposer.vue';
import { crmState } from '../crmStore';

defineProps({
  chat: { type: Object, required: true },
});

const noteMode = computed(() => crmState.noteMode && crmState.access.enabled);
</script>

<template>
  <CrmNoteComposer v-if="noteMode" :chat="chat" />
  <slot v-else />
</template>
