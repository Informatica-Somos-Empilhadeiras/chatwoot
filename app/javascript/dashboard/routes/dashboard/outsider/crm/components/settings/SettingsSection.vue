<script setup>
// OUTSIDER: cabeçalho padrão das seções de configuração do CRM.
defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div class="flex flex-col max-w-2xl gap-1">
        <h3 class="text-base font-medium text-n-slate-12">{{ title }}</h3>
        <p v-if="description" class="mb-0 text-sm text-n-slate-11">
          {{ description }}
        </p>
      </div>
      <slot name="actions" />
    </div>
    <slot />
  </div>
</template>
