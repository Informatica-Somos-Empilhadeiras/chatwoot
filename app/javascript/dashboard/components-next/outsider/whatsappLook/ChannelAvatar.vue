<script setup>
// OUTSIDER: foto do contato com o selo do canal (WhatsApp, e-mail, Instagram...) no canto de
// baixo. A foto ganha um recorte redondo em volta do selo (máscara), então o "respiro" entre os
// dois é transparente e funciona em qualquer fundo: lista, linha selecionada, tema escuro.
import { computed } from 'vue';
import Avatar from 'next/avatar/Avatar.vue';
import { channelBadge } from 'dashboard/helper/outsider/channelBadge';

const props = defineProps({
  name: { type: String, default: '' },
  src: { type: String, default: '' },
  size: { type: Number, default: 48 },
  inbox: { type: Object, default: null },
  showBadge: { type: Boolean, default: true },
});

const badge = computed(() => (props.showBadge ? channelBadge(props.inbox) : null));

const GAP = 2;
const geometry = computed(() => {
  const badgeSize = Math.max(14, Math.round(props.size * 0.4));
  // o selo sai um pouco para fora da foto, como no WhatsApp/Telegram
  const center = props.size - badgeSize / 2 + Math.round(badgeSize * 0.12);
  return { badgeSize, center };
});

const maskStyle = computed(() => {
  if (!badge.value) return {};
  const { badgeSize, center } = geometry.value;
  const hole = badgeSize / 2 + GAP;
  const mask = `radial-gradient(circle at ${center}px ${center}px, transparent ${hole}px, #000 ${hole + 0.5}px)`;
  return { maskImage: mask, WebkitMaskImage: mask };
});

const badgeStyle = computed(() => {
  const { badgeSize, center } = geometry.value;
  return {
    width: `${badgeSize}px`,
    height: `${badgeSize}px`,
    left: `${center - badgeSize / 2}px`,
    top: `${center - badgeSize / 2}px`,
    background: badge.value.color,
  };
});

const iconStyle = computed(() => {
  const iconSize = Math.round(geometry.value.badgeSize * 0.66);
  return { width: `${iconSize}px`, height: `${iconSize}px` };
});
</script>

<template>
  <span
    class="relative inline-flex shrink-0"
    :style="{ width: `${size}px`, height: `${size}px` }"
  >
    <Avatar
      :name="name || ''"
      :src="src || ''"
      :size="size"
      rounded-full
      :style="maskStyle"
    >
      <template #badge><span /></template>
      <template v-if="$slots.overlay" #overlay="slotProps">
        <slot name="overlay" v-bind="slotProps" />
      </template>
    </Avatar>
    <span
      v-if="badge"
      v-tooltip.top="badge.label"
      class="absolute z-[2] flex items-center justify-center rounded-full text-white"
      :style="badgeStyle"
      :data-channel="badge.kind"
    >
      <span :class="badge.icon" :style="iconStyle" />
    </span>
  </span>
</template>
