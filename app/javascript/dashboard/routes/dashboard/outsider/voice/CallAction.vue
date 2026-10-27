<script setup>
// OUTSIDER: botão grande da ligação (Entrega 24), em grade como num telefone: ícone em cima e o nome
// embaixo. active pinta o botão (mudo, espera, gravando); tone escolhe a cor de quando está ligado.
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  icon: { type: String, required: true },
  label: { type: String, required: true },
  active: { type: Boolean, default: false },
  tone: { type: String, default: 'amber' },
  disabled: { type: Boolean, default: false },
});

defineEmits(['click']);

const ACTIVE = {
  amber: 'bg-n-amber-9 text-black hover:bg-n-amber-10',
  ruby: 'bg-n-ruby-9 text-white hover:bg-n-ruby-10',
  blue: 'bg-n-blue-9 text-white hover:bg-n-blue-10',
};
</script>

<template>
  <button
    type="button"
    class="flex flex-col items-center justify-center gap-1.5 min-h-[4.5rem] px-1 py-2 text-sm font-medium rounded-xl transition-colors disabled:opacity-35 disabled:cursor-not-allowed"
    :class="
      active
        ? ACTIVE[tone]
        : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 active:bg-n-alpha-4'
    "
    :disabled="disabled"
    :aria-pressed="active"
    @click="$emit('click')"
  >
    <Icon :icon="icon" class="size-6" />
    <span class="leading-tight text-center">{{ label }}</span>
  </button>
</template>
