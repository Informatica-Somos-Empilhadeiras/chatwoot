<script setup>
// OUTSIDER: painel do bloco Planilha: procura uma linha numa planilha enviada (aba Planilhas) e guarda a linha.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ConnectionSelect from './ConnectionSelect.vue';
import TemplateField from './TemplateField.vue';
import VariableName from './VariableName.vue';
import BlockTester from './BlockTester.vue';
import { useIntegrations } from './useIntegrations';
import { SHEET_OPERATORS } from './integrationTypes';
import { braces } from './template';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t } = useI18n();
const store = useIntegrations();
const data = computed(() => props.node.data);

const dataset = computed(() =>
  store.datasets.find(item => item.id === Number(data.value.dataset_id))
);
const columns = computed(() => dataset.value?.columns || []);
const setDataset = id => {
  data.value.dataset_id = id;
  const list = store.datasets.find(item => item.id === id)?.columns || [];
  if (!list.some(column => column.key === data.value.column)) {
    data.value.column = list[0]?.key || '';
  }
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConnectionSelect
      :model-value="data.dataset_id"
      kind="dataset"
      @update:model-value="setDataset"
    />
    <label class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.COLUMN') }}
      </span>
      <select v-model="data.column" class="!mb-0" :disabled="!columns.length">
        <option value="" disabled>
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.CHOOSE') }}
        </option>
        <option v-for="column in columns" :key="column.key" :value="column.key">
          {{ column.label }}
        </option>
      </select>
    </label>
    <label class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.OPERATOR') }}
      </span>
      <select v-model="data.operator" class="!mb-0">
        <option
          v-for="operator in SHEET_OPERATORS"
          :key="operator"
          :value="operator"
        >
          {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.OPERATORS.${operator}`) }}
        </option>
      </select>
    </label>
    <TemplateField
      v-model="data.value"
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.VALUE')"
      placeholder="{{cnpj | digitos}}"
      :hint="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.VALUE_HINT')"
      :maxlength="500"
    />
    <VariableName
      v-model="data.variable"
      fallback="linha"
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.VARIABLE')"
    />
    <div v-if="columns.length" class="flex flex-wrap gap-1">
      <span
        v-for="column in columns.slice(0, 12)"
        :key="column.key"
        class="px-1.5 py-0.5 font-mono text-[11px] rounded-md bg-n-alpha-2 text-n-slate-11"
      >
        {{ braces(`${data.variable || 'linha'}.${column.key}`) }}
      </span>
    </div>
    <BlockTester :node="node" />
  </div>
</template>
