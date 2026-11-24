<script setup>
// OUTSIDER: título de seção da folha do estúdio, como no PDF: maiúsculas na cor principal e um traço curto na cor de destaque.
import { computed } from 'vue';
import { themeColor } from './printsHelpers';

const props = defineProps({
  text: { type: String, default: '' },
  theme: { type: Object, required: true },
});

const base = computed(() => Number(props.theme.size) || 9);
</script>

<template>
  <div v-if="text.trim()" :style="{ marginBottom: '7px' }">
    <div
      class="font-bold uppercase"
      :style="{
        fontFamily: 'var(--print-heading)',
        fontSize: `${base + 1}px`,
        color: themeColor(theme, 'primary'),
        letterSpacing: '0.4px',
      }"
    >
      {{ text }}
    </div>
    <div
      :style="{
        width: '28px',
        height: '2px',
        marginTop: '2px',
        background: themeColor(theme, 'accent'),
      }"
    />
  </div>
</template>
