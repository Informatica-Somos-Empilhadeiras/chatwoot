<script setup>
// OUTSIDER: curtidas e respostas de um status; abre a lista de quem foi.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  status: { type: Object, required: true },
});

const emit = defineEmits(['click']);

const { t } = useI18n();
</script>

<template>
  <button
    v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.TITLE')"
    type="button"
    class="flex items-center flex-shrink-0 gap-3 px-2 py-1 text-sm rounded-lg tabular-nums text-n-slate-12 hover:bg-n-alpha-2"
    @click="emit('click')"
  >
    <span class="flex items-center gap-1">
      <Icon icon="i-lucide-heart" class="size-4 text-n-ruby-9" />
      {{ status.reactions.length }}
    </span>
    <span class="flex items-center gap-1">
      <Icon icon="i-lucide-message-circle-reply" class="size-4 text-n-blue-9" />
      {{ status.replies.length }}
    </span>
  </button>
</template>
