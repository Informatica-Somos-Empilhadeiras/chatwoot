<script setup>
// OUTSIDER: o quadro ao lado do menu recolhido (ver useFlyout.js). Vai para o <body> para não ser
// cortado pelo menu e leva o tema dele (claro de vidro ou escuro).
import { inject, ref } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { closeFlyout, keepFlyout } from './navState';

defineProps({
  name: { type: String, required: true },
  title: { type: String, default: '' },
  icon: { type: [String, Object, Function], default: '' },
  flyStyle: { type: Object, default: () => ({}) },
});

const themeClass = inject('outsiderNavThemeClass', ref(''));
</script>

<template>
  <Teleport to="body">
    <div
      class="onav-fly"
      :class="themeClass"
      :style="flyStyle"
      :data-nav-flyout="name"
      @mouseenter="keepFlyout"
      @mouseleave="closeFlyout(120)"
    >
      <div v-if="title" class="onav-fly-t">
        <span v-if="icon" class="onav-ico">
          <Icon :icon="icon" />
        </span>
        <span class="onav-label">{{ title }}</span>
        <slot name="title-end" />
      </div>
      <div v-if="$slots.default" class="onav-fly-scroll">
        <slot />
      </div>
    </div>
  </Teleport>
</template>
