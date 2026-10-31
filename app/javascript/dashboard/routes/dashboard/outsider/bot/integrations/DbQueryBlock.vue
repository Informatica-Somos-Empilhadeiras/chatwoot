<script setup>
// OUTSIDER: painel do bloco Banco de dados: um SQL num PostgreSQL (Supabase, Railway, Neon...) com as
// {{variáveis}} indo como parâmetro, primeira linha ou lista.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ConnectionSelect from './ConnectionSelect.vue';
import TemplateField from './TemplateField.vue';
import VariableName from './VariableName.vue';
import BlockTester from './BlockTester.vue';
import { useIntegrations } from './useIntegrations';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t } = useI18n();
const store = useIntegrations();
const data = computed(() => props.node.data);

const SQL_PLACEHOLDER = [
  'SELECT nome, limite_credito, situacao',
  'FROM clientes',
  'WHERE cnpj = {{cnpj | digitos}}',
  'LIMIT 1',
].join('\n');

const connection = computed(() =>
  store.connections.find(item => item.id === Number(data.value.connection_id))
);
const variable = computed(() => data.value.variable || 'registro');
const clampLimit = () => {
  const number = Number(data.value.limit);
  data.value.limit = Number.isFinite(number)
    ? Math.min(Math.max(Math.round(number), 1), 100)
    : 20;
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConnectionSelect v-model="data.connection_id" kind="postgres" />
    <p
      v-if="connection"
      class="flex items-start gap-1.5 mb-0 text-xs"
      :class="connection.allow_write ? 'text-n-amber-11' : 'text-n-slate-11'"
    >
      <Icon
        :icon="
          connection.allow_write ? 'i-lucide-pencil-line' : 'i-lucide-lock'
        "
        class="size-3.5 mt-px shrink-0"
      />
      {{
        connection.allow_write
          ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DB.WRITABLE')
          : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DB.READ_ONLY')
      }}
    </p>
    <TemplateField
      v-model="data.sql"
      multiline
      mono
      :rows="7"
      label="SQL"
      :placeholder="SQL_PLACEHOLDER"
      :hint="
        t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DB.SQL_HINT', {
          example: 'WHERE cnpj = {{cnpj | digitos}}',
        })
      "
    />
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DB.MODE') }}
      </span>
      <label
        v-for="mode in ['first', 'all']"
        :key="mode"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <input v-model="data.mode" type="radio" :value="mode" class="!mb-0" />
        {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.DB.MODES.${mode}`) }}
        <input
          v-if="mode === 'all' && data.mode === 'all'"
          v-model.number="data.limit"
          type="number"
          min="1"
          max="100"
          class="!mb-0 !h-7 !w-16 !text-xs"
          @blur="clampLimit"
        />
      </label>
    </div>
    <VariableName
      v-model="data.variable"
      fallback="registro"
      :hint="
        t(
          data.mode === 'all'
            ? 'OUTSIDER_TOOLS.BOT.INTEGRATIONS.DB.VARIABLE_HINT_ALL'
            : 'OUTSIDER_TOOLS.BOT.INTEGRATIONS.DB.VARIABLE_HINT_FIRST',
          {
            first: `{{${variable}.nome}}`,
            item: `{{${variable}.0.nome}}`,
            count: `{{${variable}_linhas}}`,
          }
        )
      "
    />
    <BlockTester :node="node" />
  </div>
</template>
