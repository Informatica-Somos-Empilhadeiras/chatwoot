<script setup>
// OUTSIDER: camada de seleção de uma mensagem (ver composables/outsider/useMessageSelection.js).
// Fora do modo seleção não desenha nada; só registra os dados da mensagem. No modo seleção cobre a
// linha inteira: a caixinha fica à esquerda e o clique em qualquer ponto marca ou desmarca.
import { computed, onBeforeUnmount, watch } from 'vue';
import {
  selection,
  isSelected,
  toggleSelected,
  registerMessage,
  unregisterMessage,
} from 'dashboard/composables/outsider/useMessageSelection';

const props = defineProps({
  message: { type: Object, required: true },
  canForward: { type: Boolean, default: false },
});

const snapshot = () => ({
  id: props.message.id,
  conversationId: props.message.conversationId,
  inboxId: props.message.inboxId,
  content: props.message.content || '',
  attachments: props.message.attachments || [],
  createdAt: props.message.createdAt,
  messageType: props.message.messageType,
  isPrivate: !!props.message.private,
  senderName: props.message.sender?.name || '',
  canForward: props.canForward,
});

watch(
  () => props.message.id,
  (id, oldId) => {
    if (oldId) unregisterMessage(oldId, snapshot);
    registerMessage(id, snapshot);
  },
  { immediate: true }
);
onBeforeUnmount(() => unregisterMessage(props.message.id, snapshot));

const isActive = computed(
  () =>
    selection.active &&
    selection.conversationId === props.message.conversationId &&
    props.message.messageType !== 2
);
const checked = computed(() => isSelected(props.message.id));
</script>

<template>
  <div
    v-if="isActive"
    class="absolute -top-1 -bottom-1 z-20 cursor-pointer -inset-x-4 ltr:pl-4 rtl:pr-4 flex items-center transition-colors"
    :class="
      checked
        ? 'bg-[#25D366]/10 dark:bg-[#25D366]/[0.08]'
        : 'hover:bg-n-alpha-1'
    "
    data-select-layer
    :data-checked="checked"
    @click.stop.prevent="toggleSelected(message.id)"
    @contextmenu.stop.prevent
  >
    <span
      class="grid rounded-md size-5 place-items-center shrink-0 border-2 transition-colors"
      :class="
        checked
          ? 'bg-[#25D366] border-[#25D366] text-white'
          : 'border-n-slate-8 bg-n-background'
      "
    >
      <span v-if="checked" class="i-lucide-check size-3.5" />
    </span>
  </div>
</template>
