<script setup>
// OUTSIDER: miniatura de um modelo de relatório na lista: uma folhinha com as cores do modelo e um traço por bloco, na
// ordem em que saem (cabeçalho, campos, tabelas, fotos...).
import { computed } from 'vue';
import { contrastColor, themeColor } from './printsHelpers';

const props = defineProps({
  template: { type: Object, required: true },
});

const theme = computed(() => props.template.theme || {});
const color = name => themeColor(theme.value, name);
const types = computed(() => (props.template.block_types || []).slice(0, 14));
</script>

<template>
  <div
    class="flex flex-col gap-[3px] p-2 overflow-hidden bg-white rounded shadow-sm w-[92px] h-[130px] shrink-0 outline outline-1 outline-n-weak"
  >
    <template v-for="(type, index) in types" :key="index">
      <div v-if="type === 'header'" class="flex flex-col gap-[2px]">
        <div class="flex items-center justify-between">
          <span
            class="w-5 h-2.5 rounded-sm"
            :style="{ background: color('primary') }"
          />
          <span class="flex flex-col items-end gap-[1px]">
            <span class="w-8 h-[2px] bg-slate-300" />
            <span class="w-6 h-[2px] bg-slate-200" />
          </span>
        </div>
        <span
          class="w-10 h-[3px] rounded-sm"
          :style="{ background: color('primary') }"
        />
        <span
          class="w-full h-[1px]"
          :style="{ background: color('primary') }"
        />
      </div>
      <div
        v-else-if="type === 'fields'"
        class="grid grid-cols-3 gap-[1px] p-[1px]"
        :style="{ outline: `0.5px solid ${color('line')}` }"
      >
        <span v-for="cell in 3" :key="cell" class="h-[5px] bg-slate-100" />
      </div>
      <div
        v-else-if="type === 'table' || type === 'totals'"
        class="flex flex-col gap-[1px]"
      >
        <span class="h-[3px]" :style="{ background: color('primary') }" />
        <span class="h-[3px]" :style="{ background: color('row') }" />
        <span class="h-[3px] bg-slate-100" />
      </div>
      <div v-else-if="type === 'checklist'" class="flex flex-col gap-[2px]">
        <span
          class="h-[4px] rounded-[1px]"
          :style="{
            background: color('primary'),
            color: contrastColor(theme, 'primary'),
          }"
        />
        <span class="grid grid-cols-3 gap-[2px]">
          <span
            v-for="cell in 3"
            :key="cell"
            class="h-[10px] rounded-[1px] bg-slate-300"
          />
        </span>
      </div>
      <span
        v-else-if="type === 'long_text'"
        class="h-[8px] rounded-[1px]"
        :style="{ background: color('box') }"
      />
      <span v-else-if="type === 'signatures'" class="flex gap-2 pt-1.5">
        <span class="flex-1 h-[1px] bg-slate-500" />
        <span class="flex-1 h-[1px] bg-slate-500" />
      </span>
      <span
        v-else-if="type === 'divider'"
        class="h-[1px]"
        :style="{ background: color('line') }"
      />
      <span
        v-else-if="type === 'heading'"
        class="w-12 h-[3px] rounded-sm"
        :style="{ background: color('primary') }"
      />
      <span v-else-if="type === 'text'" class="h-[2px] bg-slate-200" />
      <span
        v-else-if="type === 'image'"
        class="w-8 h-[10px] mx-auto rounded-[1px] bg-slate-200"
      />
      <span
        v-else-if="type === 'page_break'"
        class="border-t border-dashed border-slate-300"
      />
    </template>
  </div>
</template>
