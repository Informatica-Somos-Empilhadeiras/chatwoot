<script setup>
// OUTSIDER: texto do modelo na folha do editor, como o PDF desenha: **negrito**, ==destaque amarelo== e os
// campos automáticos ({cliente.empresa}...) como etiquetas azuis, que o PDF troca pelos dados da proposta.
import { computed } from 'vue';

const props = defineProps({
  text: { type: String, default: '' },
  placeholder: { type: String, default: '' },
});

const MARKS = /(\*\*\S(?:[^*\n]*\S)?\*\*|==\S(?:[^=\n]*\S)?==)/;
const FIELDS = /(\{[a-z_]+\.[a-z_]+\})/;

const withFields = (text, style) =>
  text
    .split(FIELDS)
    .filter(Boolean)
    .map(part =>
      FIELDS.test(part)
        ? { ...style, text: part.slice(1, -1), field: true }
        : { ...style, text: part }
    );

const parts = computed(() =>
  String(props.text || '')
    .split(MARKS)
    .filter(Boolean)
    .flatMap(part => {
      if (part.startsWith('**') && part.endsWith('**') && part.length > 4) {
        return withFields(part.slice(2, -2), { bold: true });
      }
      if (part.startsWith('==') && part.endsWith('==') && part.length > 4) {
        return withFields(part.slice(2, -2), { highlight: true });
      }
      return withFields(part, {});
    })
);
</script>

<template>
  <span class="whitespace-pre-wrap break-words">
    <template v-for="(part, index) in parts" :key="index">
      <span
        v-if="part.field"
        class="inline-block px-1 mx-px leading-tight align-baseline rounded bg-[#dbeafe] text-[#1e40af] text-[0.85em]"
        :class="{ 'font-bold': part.bold }"
        >{{ part.text }}</span
      >
      <span
        v-else
        :class="{ 'font-bold': part.bold, 'bg-[#ffff00]': part.highlight }"
        >{{ part.text }}</span
      >
    </template>
    <span v-if="!parts.length && placeholder" class="italic text-slate-400">
      {{ placeholder }}
    </span>
  </span>
</template>
