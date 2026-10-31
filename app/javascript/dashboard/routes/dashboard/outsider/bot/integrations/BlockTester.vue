<script setup>
// OUTSIDER: "Testar este bloco" no painel do bloco de integração. Roda só este bloco no servidor
// (run_block) com os valores de teste das variáveis que ele usa, sem mandar nada a cliente nenhum, e mostra
// a saída, o que ficou guardado e a resposta do sistema. O que altera dados de verdade pergunta antes.
// Os valores guardados ficam para testar os próximos blocos.
import { ref, computed, inject, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import BotFlowsAPI from 'dashboard/api/outsider/botFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JsonTree from './JsonTree.vue';
import { braces } from './template';
import {
  blockVariables,
  errorText,
  parseTestValue,
  showValue,
  PORT_TONES,
  integrationPorts,
} from './integrationTypes';

const props = defineProps({
  node: { type: Object, required: true },
  pickable: { type: Boolean, default: false },
});

const emit = defineEmits(['pick']);

const { t, te } = useI18n();
const testValues = inject('botTestValues', reactive({}));
const flowId = inject('botFlowId', ref(null));

const isRunning = ref(false);
const result = ref(null);
const failure = ref('');
const confirming = ref(false);

const used = computed(() => blockVariables(props.node));
const portLabel = port =>
  integrationPorts(props.node, t).find(item => item.id === port)?.label || port;

const variablesPayload = () =>
  Object.fromEntries(
    Object.entries(testValues)
      .filter(([, value]) => String(value ?? '') !== '')
      .map(([key, value]) => [key, parseTestValue(value)])
  );

const remember = variables => {
  Object.entries(variables || {}).forEach(([key, value]) => {
    if (key === 'erro' || value === null || value === undefined) return;
    testValues[key] = showValue(value);
  });
};

const run = async (confirmWrite = false) => {
  isRunning.value = true;
  failure.value = '';
  confirming.value = false;
  try {
    const { data } = await BotFlowsAPI.runBlock({
      node: { id: props.node.id, type: props.node.type, data: props.node.data },
      variables: variablesPayload(),
      flow_id: flowId.value,
      confirm_write: confirmWrite,
    });
    if (data.needs_confirmation) {
      confirming.value = true;
      result.value = null;
      return;
    }
    result.value = data;
    remember(data.variables);
  } catch (error) {
    result.value = null;
    failure.value =
      error?.response?.data?.message ||
      t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.FAILED');
  } finally {
    isRunning.value = false;
  }
};

const shownVariables = computed(() =>
  Object.entries(result.value?.variables || {}).filter(
    ([key, value]) => key !== 'erro' && value !== null && value !== ''
  )
);
const errorCode = computed(() => result.value?.variables?.erro || '');
const response = computed(() => result.value?.response || null);
const truncate = text => (text.length > 160 ? `${text.slice(0, 160)}…` : text);
</script>

<template>
  <section
    class="flex flex-col gap-2.5 p-3 border rounded-xl border-n-weak bg-n-alpha-1"
  >
    <div class="flex items-center gap-2">
      <Icon icon="i-lucide-flask-conical" class="size-4 text-n-teal-10" />
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.TITLE') }}
      </span>
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.HINT') }}
    </p>
    <div v-if="used.length" class="flex flex-col gap-1.5">
      <label
        v-for="name in used"
        :key="name"
        class="flex items-center gap-2 text-xs"
      >
        <span class="w-24 font-mono truncate shrink-0 text-n-slate-11">
          {{ braces(name) }}
        </span>
        <input
          v-model="testValues[name]"
          type="text"
          class="flex-1 min-w-0 !mb-0 !h-8 !text-xs"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.VALUE')"
        />
      </label>
      <span class="text-[11px] text-n-slate-10">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.JSON_HINT') }}
      </span>
    </div>
    <Button
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.RUN')"
      icon="i-lucide-play"
      sm
      teal
      faded
      class="self-start"
      :is-loading="isRunning"
      @click="run(false)"
    />

    <div
      v-if="confirming"
      class="flex flex-col gap-2 p-2.5 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
    >
      <span class="flex items-start gap-1.5">
        <Icon icon="i-lucide-triangle-alert" class="size-3.5 mt-px shrink-0" />
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.CONFIRM_WRITE') }}
      </span>
      <div class="flex gap-2">
        <Button
          :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.RUN_FOR_REAL')"
          xs
          amber
          @click="run(true)"
        />
        <Button
          :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.CANCEL')"
          xs
          faded
          slate
          @click="confirming = false"
        />
      </div>
    </div>

    <p v-if="failure" class="mb-0 text-xs text-n-ruby-11">{{ failure }}</p>

    <div v-if="result" class="flex flex-col gap-2">
      <div class="flex flex-wrap items-center gap-1.5 text-xs">
        <span
          class="px-2 py-0.5 rounded-md font-medium"
          :class="PORT_TONES[result.port] || 'bg-n-alpha-2 text-n-slate-12'"
        >
          {{
            t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.PORT', {
              port: portLabel(result.port),
            })
          }}
        </span>
        <template v-if="response">
          <span class="px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-12">
            {{ response.status }}
          </span>
          <span class="text-n-slate-11">
            {{
              response.cached
                ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.CACHED')
                : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.DURATION', {
                    ms: response.duration_ms,
                  })
            }}
          </span>
        </template>
      </div>
      <span
        v-if="response?.url"
        class="font-mono text-[11px] break-all text-n-slate-10"
      >
        {{ response.url }}
      </span>
      <p
        v-if="errorCode"
        class="flex items-start gap-1.5 mb-0 text-xs text-n-ruby-11"
      >
        <Icon icon="i-lucide-circle-x" class="size-3.5 mt-px shrink-0" />
        {{ errorText(errorCode, t, te) }}
      </p>
      <div
        v-if="result.preview"
        class="flex items-center gap-2 px-2.5 py-2 text-xs rounded-lg bg-n-solid-1 text-n-slate-12"
      >
        <Icon icon="i-lucide-file-text" class="size-4 shrink-0" />
        {{
          t(
            `OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.PREVIEW_${result.preview.mode === 'link' ? 'LINK' : 'FILE'}`,
            { name: result.preview.name }
          )
        }}
      </div>
      <div v-if="result.choice?.length" class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-12">
          {{
            t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.DOCUMENTS', {
              count: result.choice.length,
            })
          }}
        </span>
        <span
          v-for="doc in result.choice"
          :key="doc.caminho"
          class="flex items-center gap-1.5 text-xs text-n-slate-11"
        >
          <Icon icon="i-lucide-file" class="size-3.5 shrink-0" />
          <span class="truncate">{{ doc.caminho }}</span>
        </span>
      </div>
      <div v-if="shownVariables.length" class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.SAVED') }}
        </span>
        <span
          v-for="[key, value] in shownVariables"
          :key="key"
          class="font-mono text-[11px] break-all text-n-slate-11"
        >
          <span class="text-n-slate-12">{{ braces(key) }}</span>
          = {{ truncate(showValue(value)) }}
        </span>
      </div>
      <div
        v-if="response?.json !== undefined && response?.json !== null"
        class="flex flex-col gap-1"
      >
        <span class="text-xs font-medium text-n-slate-12">
          {{
            pickable
              ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.RESPONSE_PICK')
              : t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.TEST.RESPONSE')
          }}
        </span>
        <div
          class="p-2 overflow-auto rounded-lg max-h-80 bg-n-solid-1 border border-n-weak"
        >
          <JsonTree
            :value="response.json"
            :pickable="pickable"
            @pick="path => emit('pick', path)"
          />
        </div>
      </div>
      <pre
        v-else-if="response?.text"
        class="p-2 mb-0 overflow-auto font-mono text-[11px] whitespace-pre-wrap rounded-lg max-h-60 bg-n-solid-1 text-n-slate-11"
        >{{ response.text }}</pre
      >
    </div>
  </section>
</template>
