<script setup>
// OUTSIDER: painel do bloco API: conexão, REST (método, caminho, parâmetros, corpo) ou GraphQL, onde guardar a
// resposta e quais campos viram variáveis (clicando na resposta do teste).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ConnectionSelect from './ConnectionSelect.vue';
import TemplateField from './TemplateField.vue';
import KeyValueRows from './KeyValueRows.vue';
import VariableName from './VariableName.vue';
import BlockTester from './BlockTester.vue';
import { useIntegrations } from './useIntegrations';
import { segments, variableName } from './template';
import { WRITE_METHODS, apiWrites, isGraphql } from './integrationTypes';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t } = useI18n();
const store = useIntegrations();
const data = computed(() => props.node.data);

const METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
const BODY_TYPES = ['none', 'json', 'form', 'xml', 'text'];
const CACHE_OPTIONS = [0, 60, 300, 900, 3600];
const JSON_PLACEHOLDER = [
  '{',
  '  "cnpj": "{{cnpj | digitos}}",',
  '  "telefone": "{{contato.telefone}}"',
  '}',
].join('\n');
const TIMEOUT_OPTIONS = [0, 5, 10, 20, 30];
// exemplos nos campos (técnicos, iguais em todo idioma)
const EXAMPLES = { path: 'dados.status', variable: 'status' };

const connection = computed(() =>
  store.connections.find(item => item.id === Number(data.value.connection_id))
);
const graphql = computed(() => isGraphql(data.value));
const readOnlyBlocked = computed(
  () =>
    connection.value && !connection.value.allow_write && apiWrites(data.value)
);
const cacheable = computed(() =>
  graphql.value ? !apiWrites(data.value) : data.value.method === 'GET'
);

const setKind = kind => {
  if (kind === 'graphql' && !graphql.value) {
    data.value.body_type = 'graphql';
    data.value.method = 'POST';
    if (!data.value.path) data.value.path = '/graphql';
  } else if (kind === 'rest' && graphql.value) {
    data.value.body_type = 'none';
    data.value.method = 'GET';
  }
};

const setMethod = method => {
  data.value.method = method;
  if (method === 'GET') data.value.body_type = 'none';
  else if (data.value.body_type === 'none') data.value.body_type = 'json';
};

// confere o JSON com as {{variáveis}} trocadas por valores de exemplo
const jsonProblem = text => {
  const source = String(text || '');
  if (!source.trim()) return '';
  let out = '';
  let inString = false;
  let escaped = false;
  for (let index = 0; index < source.length; ) {
    const end = source.startsWith('{{', index)
      ? source.indexOf('}}', index)
      : -1;
    if (end > 0) {
      out += inString ? 'x' : '0';
      index = end + 2;
    } else {
      const char = source[index];
      if (escaped) escaped = false;
      else if (inString && char === '\\') escaped = true;
      else if (char === '"') inString = !inString;
      out += char;
      index += 1;
    }
  }
  try {
    JSON.parse(out);
    return '';
  } catch (error) {
    return t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.JSON_ERROR', {
      error: error.message,
    });
  }
};
const bodyError = computed(() =>
  data.value.body_type === 'json' || graphql.value
    ? jsonProblem(data.value.body)
    : ''
);

const addMapping = path => {
  const parts = segments(path).filter(part => !/^\d+$/.test(part));
  const base = variableName(parts[parts.length - 1] || 'campo', 'campo');
  const taken = new Set((data.value.mappings || []).map(item => item.variable));
  if ((data.value.mappings || []).some(item => item.path === path)) return;
  let name = base;
  for (let number = 2; taken.has(name); number += 1) name = `${base}_${number}`;
  data.value.mappings = [
    ...(data.value.mappings || []),
    { path, variable: name },
  ];
};
const removeMapping = index => {
  data.value.mappings = data.value.mappings.filter(
    (_, position) => position !== index
  );
};
const tidyMapping = item => {
  item.variable = variableName(item.variable, 'campo');
};

const pathHint = computed(() =>
  connection.value
    ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.PATH_HINT', {
        url: `${connection.value.base_url}${data.value.path || ''}`,
      })
    : ''
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConnectionSelect v-model="data.connection_id" kind="http" />

    <div class="grid grid-cols-2 gap-1.5">
      <button
        v-for="kind in ['rest', 'graphql']"
        :key="kind"
        type="button"
        class="px-2 py-1.5 text-xs border rounded-lg"
        :class="
          (kind === 'graphql') === graphql
            ? 'border-n-brand bg-n-brand/5 text-n-slate-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="setKind(kind)"
      >
        {{
          t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.KIND_${kind.toUpperCase()}`)
        }}
      </button>
    </div>

    <template v-if="!graphql">
      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.METHOD') }}
        </span>
        <div class="flex flex-wrap gap-1">
          <button
            v-for="method in METHODS"
            :key="method"
            type="button"
            class="px-2 py-1 font-mono text-xs border rounded-md"
            :class="
              data.method === method
                ? 'border-n-brand bg-n-brand/5 text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="setMethod(method)"
          >
            {{ method }}
          </button>
        </div>
        <span class="text-xs text-n-slate-10">
          {{
            WRITE_METHODS.includes(data.method)
              ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.WRITE_HINT')
              : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.READ_HINT')
          }}
        </span>
      </div>
      <TemplateField
        v-model="data.path"
        mono
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.PATH')"
        placeholder="/pedidos/{{numero_pedido}}"
        :hint="pathHint"
        :maxlength="1000"
      />
      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.QUERY') }}
        </span>
        <KeyValueRows
          v-model="data.query"
          key-placeholder="cnpj"
          value-placeholder="{{cnpj | digitos}}"
        />
      </div>
      <div v-if="data.method !== 'GET'" class="flex flex-col gap-2">
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.BODY') }}
          </span>
          <select v-model="data.body_type" class="!mb-0">
            <option v-for="type in BODY_TYPES" :key="type" :value="type">
              {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.BODY_TYPES.${type}`) }}
            </option>
          </select>
        </label>
        <KeyValueRows
          v-if="data.body_type === 'form'"
          v-model="data.form"
          key-placeholder="nome"
          value-placeholder="{{contato.nome}}"
        />
        <TemplateField
          v-else-if="data.body_type !== 'none'"
          v-model="data.body"
          multiline
          mono
          :rows="6"
          :placeholder="data.body_type === 'json' ? JSON_PLACEHOLDER : ''"
          :error="bodyError"
          :hint="
            data.body_type === 'json'
              ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.JSON_HINT')
              : ''
          "
        />
      </div>
    </template>

    <template v-else>
      <TemplateField
        v-model="data.path"
        mono
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.ENDPOINT')"
        placeholder="/graphql"
        :hint="pathHint"
        :maxlength="1000"
      />
      <TemplateField
        v-model="data.graphql_query"
        multiline
        mono
        :rows="7"
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.GRAPHQL_QUERY')"
        placeholder="query ($id: ID!) {
  pedido(id: $id) { status total }
}"
        :hint="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.GRAPHQL_HINT')"
      />
      <TemplateField
        v-model="data.body"
        multiline
        mono
        :rows="3"
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.GRAPHQL_VARIABLES')"
        placeholder='{ "id": "{{numero_pedido}}" }'
        :error="bodyError"
      />
    </template>

    <p
      v-if="readOnlyBlocked"
      class="flex items-start gap-1.5 p-2 mb-0 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
    >
      <Icon icon="i-lucide-lock" class="size-3.5 mt-px shrink-0" />
      {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.READ_ONLY') }}
    </p>

    <VariableName
      v-model="data.variable"
      fallback="resultado"
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.VARIABLE')"
      :hint="
        t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.VARIABLE_HINT', {
          variable: `{{${data.variable || 'resultado'}}}`,
          status: `{{${data.variable || 'resultado'}_status}}`,
        })
      "
    />

    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.MAPPINGS') }}
      </span>
      <span class="text-xs text-n-slate-10">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.MAPPINGS_HINT') }}
      </span>
      <div
        v-for="(item, index) in data.mappings"
        :key="index"
        class="flex items-center gap-1"
      >
        <input
          v-model="item.path"
          type="text"
          spellcheck="false"
          class="flex-1 min-w-0 !mb-0 !h-8 font-mono !text-xs"
          :placeholder="EXAMPLES.path"
        />
        <Icon
          icon="i-lucide-arrow-right"
          class="size-3.5 shrink-0 text-n-slate-10"
        />
        <input
          v-model="item.variable"
          type="text"
          spellcheck="false"
          maxlength="30"
          class="!w-36 min-w-0 !mb-0 !h-8 font-mono !text-xs"
          :placeholder="EXAMPLES.variable"
          @blur="tidyMapping(item)"
        />
        <Button
          icon="i-lucide-x"
          xs
          ghost
          slate
          @click="removeMapping(index)"
        />
      </div>
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.ADD_ROW')"
        icon="i-lucide-plus"
        xs
        faded
        slate
        class="self-start"
        :disabled="(data.mappings || []).length >= 20"
        @click="
          data.mappings = [...(data.mappings || []), { path: '', variable: '' }]
        "
      />
    </div>

    <details class="group">
      <summary
        class="text-sm font-medium cursor-pointer select-none text-n-slate-12"
      >
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.ADVANCED') }}
      </summary>
      <div class="flex flex-col gap-3 pt-3">
        <div class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.HEADERS') }}
          </span>
          <KeyValueRows
            v-model="data.headers"
            key-placeholder="X-Empresa"
            value-placeholder="somos"
          />
        </div>
        <label v-if="cacheable" class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.CACHE') }}
          </span>
          <select v-model.number="data.cache_seconds" class="!mb-0">
            <option
              v-for="seconds in CACHE_OPTIONS"
              :key="seconds"
              :value="seconds"
            >
              {{
                t(
                  `OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.CACHE_OPTIONS.${seconds}`
                )
              }}
            </option>
          </select>
          <span class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.CACHE_HINT') }}
          </span>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.TIMEOUT') }}
          </span>
          <select v-model.number="data.timeout_seconds" class="!mb-0">
            <option
              v-for="seconds in TIMEOUT_OPTIONS"
              :key="seconds"
              :value="seconds"
            >
              {{
                seconds
                  ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.SECONDS', {
                      seconds,
                    })
                  : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.API.TIMEOUT_DEFAULT')
              }}
            </option>
          </select>
        </label>
      </div>
    </details>

    <BlockTester :node="node" pickable @pick="addMapping" />
  </div>
</template>
