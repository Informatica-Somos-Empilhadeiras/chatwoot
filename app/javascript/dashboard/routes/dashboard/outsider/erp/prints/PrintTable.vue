<script setup>
// OUTSIDER: tabela da folha do estúdio (produtos, itens, check-in, respostas do checklist), como no PDF: cabeçalho na cor
// principal, linhas zebradas e o alinhamento de cada coluna do catálogo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { contrastColor, themeColor } from './printsHelpers';

const props = defineProps({
  columns: { type: Array, required: true },
  rows: { type: Array, required: true },
  theme: { type: Object, required: true },
  striped: { type: Boolean, default: true },
});

const { t } = useI18n();
const base = computed(() => Number(props.theme.size) || 9);
const line = computed(() => `0.5px solid ${themeColor(props.theme, 'line')}`);
</script>

<template>
  <table
    class="w-full border-collapse"
    :style="{ fontSize: `${base - 0.5}px`, lineHeight: 1.3 }"
  >
    <thead>
      <tr
        :style="{
          background: themeColor(theme, 'primary'),
          color: contrastColor(theme, 'primary'),
        }"
      >
        <th
          v-for="column in columns"
          :key="column.key"
          class="font-bold"
          :style="{
            padding: '4px 5px',
            textAlign: column.align || 'left',
            border: `0.5px solid ${themeColor(theme, 'primary')}`,
          }"
        >
          {{ column.label }}
        </th>
      </tr>
    </thead>
    <tbody>
      <tr v-if="!rows.length">
        <td
          :colspan="columns.length"
          :style="{ padding: '4px 5px', border: line }"
        >
          {{ t('OUTSIDER_ERP.PRINTS.CANVAS.NO_ITEMS') }}
        </td>
      </tr>
      <tr
        v-for="(row, index) in rows"
        :key="index"
        :style="{
          background:
            striped && index % 2 === 1
              ? themeColor(theme, 'row')
              : 'transparent',
        }"
      >
        <td
          v-for="column in columns"
          :key="column.key"
          :style="{
            padding: '4px 5px',
            textAlign: column.align || 'left',
            border: line,
          }"
        >
          {{ row[column.key] }}
        </td>
      </tr>
    </tbody>
  </table>
</template>
