<script setup>
// OUTSIDER: painel do bloco Buscar na planilha. A planilha (Excel ou CSV) é enviada aqui mesmo, arrastando ou
// escolhendo o arquivo, ou escolhida entre as já enviadas (aba Planilhas). O bloco procura uma linha e
// guarda as colunas em variáveis.
import { computed, inject, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BotDatasetsAPI from 'dashboard/api/outsider/botDatasets';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TemplateField from './TemplateField.vue';
import VariableName from './VariableName.vue';
import BlockTester from './BlockTester.vue';
import SpreadsheetUpload from './SpreadsheetUpload.vue';
import { useIntegrations } from './useIntegrations';
import { SHEET_OPERATORS } from './integrationTypes';
import { MAX_ROWS } from './spreadsheet';
import { braces } from './template';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t } = useI18n();
const store = useIntegrations();
const pendingFiles = inject('botPendingFiles', {});
const data = computed(() => props.node.data);

const uploader = ref(null);
const dragging = ref(false);
const choosing = ref(false);

const dataset = computed(() =>
  store.datasets.find(item => item.id === Number(data.value.dataset_id))
);
const missing = computed(
  () => !!data.value.dataset_id && store.loaded && !dataset.value
);
const others = computed(() =>
  store.datasets.filter(item => item.id !== dataset.value?.id)
);
const columns = computed(() => dataset.value?.columns || []);

const setDataset = id => {
  data.value.dataset_id = id;
  choosing.value = false;
  const list = store.datasets.find(item => item.id === id)?.columns || [];
  if (!list.some(column => column.key === data.value.column)) {
    data.value.column = list[0]?.key || '';
  }
};

const onDrop = event => {
  dragging.value = false;
  const [file] = event.dataTransfer?.files || [];
  if (file) uploader.value?.start(file, null);
};

const onChoose = event => {
  const { value } = event.target;
  // eslint-disable-next-line no-param-reassign
  event.target.value = '';
  if (value === 'new') {
    uploader.value?.pick(null);
  } else if (value) {
    setDataset(Number(value));
  }
};

const formatDate = seconds =>
  new Date(seconds * 1000).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });

// as primeiras linhas, para conferir se é a planilha certa
const preview = ref([]);
const previewColumns = computed(() => columns.value.slice(0, 4));
watch(
  () => `${dataset.value?.id || ''}:${dataset.value?.updated_at || ''}`,
  async () => {
    const current = dataset.value;
    preview.value = [];
    if (!current?.rows_count) return;
    try {
      const { data: found } = await BotDatasetsAPI.search(current.id, '');
      if (dataset.value?.id === current.id) {
        preview.value = (found.rows || []).slice(0, 3);
      }
    } catch {
      preview.value = [];
    }
  },
  { immediate: true }
);

// planilha solta no quadro: o bloco foi criado para ela
const takePending = () => {
  const file = pendingFiles[props.node.id];
  if (!file) return;
  delete pendingFiles[props.node.id];
  uploader.value?.start(file, null);
};
onMounted(takePending);
watch(() => props.node.id, takePending);
</script>

<template>
  <div class="flex flex-col gap-4">
    <SpreadsheetUpload ref="uploader" @uploaded="item => setDataset(item.id)" />

    <div
      v-if="dataset"
      class="flex flex-col gap-3 p-3 border rounded-xl border-n-weak bg-n-solid-2"
    >
      <div class="flex items-center gap-3">
        <span
          class="flex items-center justify-center rounded-lg size-12 shrink-0 bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-sheet" class="size-6" />
        </span>
        <div class="flex flex-col min-w-0 gap-0.5">
          <span
            class="text-sm font-medium truncate text-n-slate-12"
            :title="dataset.name"
          >
            {{ dataset.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.SIZE', {
                rows: dataset.rows_count.toLocaleString('pt-BR'),
                columns: dataset.columns.length,
              })
            }}
          </span>
          <span class="text-[11px] truncate text-n-slate-10">
            {{
              t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.UPDATED', {
                file: dataset.file_name || '—',
                date: formatDate(dataset.updated_at),
              })
            }}
          </span>
        </div>
      </div>
      <div
        v-if="preview.length"
        class="overflow-x-auto border rounded-lg border-n-weak bg-n-solid-1"
      >
        <table class="w-full text-[11px]">
          <thead>
            <tr>
              <th
                v-for="column in previewColumns"
                :key="column.key"
                class="px-2 py-1 font-medium text-left whitespace-nowrap text-n-slate-12"
              >
                {{ column.label }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, index) in preview"
              :key="index"
              class="border-t border-n-weak"
            >
              <td
                v-for="column in previewColumns"
                :key="column.key"
                class="px-2 py-1 max-w-[7rem] truncate text-n-slate-11"
                :title="row[column.key]"
              >
                {{ row[column.key] }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="flex flex-wrap items-center gap-1.5">
        <Button
          :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.REFRESH')"
          icon="i-lucide-refresh-cw"
          xs
          faded
          teal
          @click="uploader?.pick(dataset)"
        />
        <Button
          :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.SWITCH')"
          icon="i-lucide-replace"
          xs
          faded
          slate
          @click="choosing = !choosing"
        />
      </div>
      <select v-if="choosing" class="!mb-0" @change="onChoose">
        <option value="">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.CHOOSE') }}
        </option>
        <option v-for="item in others" :key="item.id" :value="item.id">
          {{ item.name }}
        </option>
        <option value="new">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.UPLOAD_OTHER') }}
        </option>
      </select>
    </div>

    <template v-else>
      <p
        v-if="missing"
        class="flex items-start gap-1.5 mb-0 text-xs text-n-amber-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 shrink-0" />
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.GONE') }}
      </p>
      <button
        type="button"
        class="flex flex-col items-center gap-2 px-4 py-6 text-center border-2 border-dashed rounded-xl transition-colors"
        :class="
          dragging
            ? 'border-n-teal-9 bg-n-teal-3'
            : 'border-n-weak hover:border-n-slate-8'
        "
        @click="uploader?.pick(null)"
        @dragover.prevent="dragging = true"
        @dragleave="dragging = false"
        @drop.prevent="onDrop"
      >
        <span
          class="flex items-center justify-center rounded-xl size-11 bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-sheet" class="size-5" />
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.DROP') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{
            t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.DROP_HINT', {
              max: MAX_ROWS.toLocaleString('pt-BR'),
            })
          }}
        </span>
      </button>
      <label v-if="store.datasets.length" class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.USE_EXISTING') }}
        </span>
        <select class="!mb-0" @change="onChoose">
          <option value="">
            {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.SHEET.CHOOSE') }}
          </option>
          <option
            v-for="item in store.datasets"
            :key="item.id"
            :value="item.id"
          >
            {{ item.name }}
          </option>
        </select>
      </label>
    </template>

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
