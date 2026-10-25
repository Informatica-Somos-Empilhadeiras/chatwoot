<script setup>
// OUTSIDER: teclado do telefone (Entrega 22): digita o número antes de ligar e envia tons (URA do cliente)
// durante a ligação.
const emit = defineEmits(['press']);

const KEYS = [
  ['1', ''],
  ['2', 'ABC'],
  ['3', 'DEF'],
  ['4', 'GHI'],
  ['5', 'JKL'],
  ['6', 'MNO'],
  ['7', 'PQRS'],
  ['8', 'TUV'],
  ['9', 'WXYZ'],
  ['*', ''],
  ['0', '+'],
  ['#', ''],
];
</script>

<template>
  <div class="grid grid-cols-3 gap-1.5">
    <button
      v-for="[digit, letters] in KEYS"
      :key="digit"
      type="button"
      class="flex flex-col items-center justify-center h-11 rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 active:bg-n-alpha-4 text-n-slate-12"
      @click="emit('press', digit)"
    >
      <span class="text-base font-medium leading-5">{{ digit }}</span>
      <span class="text-[0.625rem] leading-3 text-n-slate-10 h-3">
        {{ letters }}
      </span>
    </button>
  </div>
</template>
