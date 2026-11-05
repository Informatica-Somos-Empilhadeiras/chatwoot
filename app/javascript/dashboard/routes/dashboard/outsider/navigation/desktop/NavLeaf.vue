<script setup>
// OUTSIDER: um destino do menu lateral (ex.: Todas, uma pasta, uma aba do CRM).
// - "sub": nas opções do módulo aberto, na árvore; o ativo fica com o fundo suave;
// - "fly": no quadro ao lado do menu recolhido e na lista das Configurações, com ícone e o ativo na
//   pílula verde.
// O número é o de não lidas/pendentes que o Chatwoot já calcula.
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { shortCount, isWarnItem } from './navCounts';

const props = defineProps({
  item: { type: Object, required: true },
  active: { type: Boolean, default: false },
  count: { type: Number, default: 0 },
  variant: { type: String, default: 'sub' },
});

const emit = defineEmits(['navigate']);

// na árvore só os ícones desenhados (cor da etiqueta, logo do canal); os de linha ficam de fora
const showIcon = computed(
  () =>
    !!props.item.icon &&
    (props.variant === 'fly' || typeof props.item.icon !== 'string')
);
</script>

<template>
  <li class="onav-li">
    <RouterLink
      :to="item.to"
      :title="item.label"
      class="onav-leaf"
      :class="[`onav-leaf--${variant}`, { on: active }]"
      :aria-current="active ? 'page' : undefined"
      @click="emit('navigate')"
    >
      <span v-if="showIcon" class="onav-ico">
        <Icon :icon="item.icon" />
      </span>
      <span class="onav-label">{{ item.label }}</span>
      <span
        v-if="count"
        class="onav-pill onav-pill--sm"
        :class="{ 'onav-pill--warn': isWarnItem(item) }"
      >
        {{ shortCount(count) }}
      </span>
    </RouterLink>
  </li>
</template>
