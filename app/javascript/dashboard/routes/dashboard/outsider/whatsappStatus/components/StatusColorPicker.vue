<script setup>
// OUTSIDER: cores de fundo do status de texto.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { BACKGROUND_COLORS } from '../helpers';

const color = defineModel({ type: String, default: BACKGROUND_COLORS[0] });

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <button
      v-for="option in BACKGROUND_COLORS"
      :key="option"
      type="button"
      :title="t('OUTSIDER_WHATSAPP_STATUS.PUBLISH.COLOR')"
      class="flex items-center justify-center text-white rounded-full size-7 outline outline-2 outline-offset-2"
      :class="color === option ? 'outline-n-brand' : 'outline-transparent'"
      :style="{ backgroundColor: option }"
      @click="color = option"
    >
      <Icon v-if="color === option" icon="i-lucide-check" class="size-4" />
    </button>
  </div>
</template>
