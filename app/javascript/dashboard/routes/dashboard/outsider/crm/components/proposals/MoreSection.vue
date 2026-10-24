<script setup>
// OUTSIDER: parte do editor que fica recolhida até a pessoa pedir (Entrega 20). O resumo ao lado do
// título diz o que tem dentro, para não precisar abrir só para conferir.
defineProps({
  label: { type: String, required: true },
  summary: { type: String, default: '' },
});

const open = defineModel('open', { type: Boolean, default: false });
</script>

<template>
  <div class="flex flex-col gap-3">
    <button
      type="button"
      class="flex items-center self-start gap-2 text-sm font-medium text-start text-n-blue-11 hover:underline"
      :aria-expanded="open"
      @click="open = !open"
    >
      <span
        class="transition-transform i-lucide-chevron-right size-4 shrink-0"
        :class="{ 'rotate-90': open }"
      />
      <span>
        {{ label }}
        <span v-if="summary && !open" class="font-normal text-n-slate-11">
          · {{ summary }}
        </span>
      </span>
    </button>
    <div v-if="open" class="flex flex-col gap-3">
      <slot />
    </div>
  </div>
</template>
