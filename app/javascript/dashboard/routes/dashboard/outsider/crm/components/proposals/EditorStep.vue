<script setup>
// OUTSIDER: um passo do editor de proposta (Entrega 20): número, título curto, dica de uma linha e o
// conteúdo. Os passos seguem a ordem em que o vendedor pensa: para quem, o quê, como paga.
defineProps({
  number: { type: Number, default: null },
  title: { type: String, required: true },
  hint: { type: String, default: '' },
});
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container sm:p-5"
  >
    <header class="flex flex-wrap items-center gap-x-3 gap-y-2">
      <span
        v-if="number"
        class="flex items-center justify-center text-sm font-semibold text-white rounded-full size-7 bg-n-brand shrink-0"
      >
        {{ number }}
      </span>
      <div class="flex flex-col flex-1 min-w-0">
        <h3 class="mb-0 text-base font-medium text-n-slate-12">{{ title }}</h3>
        <p v-if="hint" class="mb-0 text-xs text-n-slate-11">{{ hint }}</p>
      </div>
      <slot name="actions" />
    </header>
    <slot />
  </section>
</template>
