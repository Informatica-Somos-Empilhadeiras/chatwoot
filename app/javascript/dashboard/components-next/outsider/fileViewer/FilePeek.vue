<script setup>
// OUTSIDER: o começo de um documento numa área pequena (miniatura do cartão): imagem (primeira página do PDF ou a
// miniatura que o Office guarda no arquivo), texto do começo (Word, texto) como uma folha, ou as primeiras linhas de
// uma planilha. A folha é sempre branca, como o papel, também no tema escuro. Embaixo, um esmaecido indica que continua.
defineProps({
  peek: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});
</script>

<template>
  <div class="relative w-full h-full overflow-hidden bg-white">
    <div
      v-if="loading || !peek"
      class="absolute inset-0 animate-pulse bg-n-slate-3"
    />
    <img
      v-else-if="peek.type === 'image'"
      :src="peek.src"
      alt=""
      class="object-cover object-top w-full h-full"
      draggable="false"
    />
    <div
      v-else-if="peek.type === 'text'"
      class="px-4 pt-3 text-[9.5px] leading-[1.45] text-[#3b3f45] text-start"
      :class="peek.mono ? 'font-mono whitespace-pre' : ''"
    >
      <template v-for="(line, index) in peek.lines" :key="index">
        <div
          v-if="line.r"
          class="grid gap-px mb-px bg-[#d6d9de] border border-[#d6d9de]"
          :style="{
            gridTemplateColumns: `repeat(${line.r.length}, minmax(0, 1fr))`,
          }"
        >
          <span
            v-for="(cell, cellIndex) in line.r"
            :key="cellIndex"
            class="px-1 truncate bg-white !text-[9px]"
          >
            {{ cell }}
          </span>
        </div>
        <p
          v-else
          class="!mb-[3px] truncate min-h-[13px]"
          :class="
            line.h
              ? '!text-[11px] !leading-[1.35] font-semibold text-[#111418] mt-0.5'
              : '!text-[9.5px] !leading-[1.45]'
          "
        >
          {{ line.t }}
        </p>
      </template>
    </div>
    <table
      v-else-if="peek.type === 'table'"
      class="w-full text-[9.5px] leading-tight text-[#3b3f45] border-collapse table-fixed"
    >
      <tbody>
        <tr
          v-for="(row, index) in peek.rows"
          :key="index"
          :class="
            index === 0 ? 'bg-[#e8f3ec] font-semibold text-[#14532d]' : ''
          "
        >
          <td
            v-for="(cell, cellIndex) in row"
            :key="cellIndex"
            class="px-1.5 py-[3px] truncate border border-[#dfe3e6]"
          >
            {{ cell }}
          </td>
        </tr>
      </tbody>
    </table>
    <div
      v-if="peek && peek.type !== 'image'"
      class="absolute inset-x-0 bottom-0 h-8 pointer-events-none bg-gradient-to-t from-white"
    />
  </div>
</template>
