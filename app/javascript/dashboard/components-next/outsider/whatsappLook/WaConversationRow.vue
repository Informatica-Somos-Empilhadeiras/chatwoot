<script setup>
// OUTSIDER: linha da lista de conversas quando ela ocupa a tela toda (sem conversa aberta ao lado).
// Entra no lugar do ConversationCardExpanded.vue do Chatwoot (troca de import no
// ConversationItem.vue), com as mesmas propriedades e eventos, e mostra o mesmo cartão da lista
// estreita (WaConversationCard) em colunas, para as duas listas parecerem a mesma coisa.
import WaConversationCard from './WaConversationCard.vue';

defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  isInboxView: { type: Boolean, default: false },
});

// o ConversationItem.vue espera, deste componente, true/false (marcar/desmarcar)
const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);
</script>

<template>
  <WaConversationCard
    wide
    :chat="chat"
    :current-contact="currentContact"
    :assignee="assignee"
    :inbox="inbox"
    :selected="selected"
    :is-active-chat="isActiveChat"
    :show-assignee="showAssignee"
    :show-inbox-name="showInboxName && !isInboxView"
    @click="emit('click', $event)"
    @contextmenu="emit('contextmenu', $event)"
    @select-conversation="emit('selectConversation', true)"
    @de-select-conversation="emit('deSelectConversation', false)"
  />
</template>
