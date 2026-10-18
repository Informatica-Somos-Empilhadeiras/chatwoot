<script setup>
// OUTSIDER: botão do cabeçalho que abre a busca dentro da conversa (lupa com
// contorno verde para ser fácil de achar; cheia enquanto a busca está aberta).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import {
  closeSearch,
  historyState,
  openSearch,
} from 'dashboard/composables/outsider/useConversationHistory';

const props = defineProps({
  conversationId: { type: Number, required: true },
});

const { t } = useI18n();

const isOpen = computed(
  () =>
    historyState.searchOpen &&
    historyState.conversationId === props.conversationId
);

const toggle = () => (isOpen.value ? closeSearch() : openSearch());
</script>

<template>
  <NextButton
    v-tooltip.bottom="t('CONVERSATION.OUTSIDER_HISTORY.SEARCH_BUTTON')"
    icon="i-lucide-search"
    size="sm"
    color="teal"
    :variant="isOpen ? 'solid' : 'outline'"
    @click="toggle"
  />
</template>
