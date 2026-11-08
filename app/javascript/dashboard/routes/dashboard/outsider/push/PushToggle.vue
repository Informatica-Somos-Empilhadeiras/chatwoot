<script setup>
// OUTSIDER: chave liga/desliga das Notificações (verde para o WhatsApp, roxo para o Teams e o Chatwoot).
defineProps({
  modelValue: { type: Boolean, default: false },
  tone: { type: String, default: 'green' },
});
const emit = defineEmits(['toggle']);

const TONES = {
  green: 'bg-[#1f9d55]',
  purple: 'bg-[#5b5fc7]',
  slate: 'bg-n-slate-11',
};
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="modelValue"
    class="relative transition-colors rounded-full w-11 h-6 shrink-0"
    :class="modelValue ? TONES[tone] || TONES.green : 'bg-n-slate-6'"
    @click="emit('toggle')"
  >
    <span
      class="absolute top-0.5 left-0.5 size-5 rounded-full bg-white shadow transition-transform"
      :class="modelValue ? 'translate-x-5' : ''"
    />
  </button>
</template>
