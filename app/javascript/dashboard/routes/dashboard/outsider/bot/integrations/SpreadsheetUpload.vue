<script setup>
// OUTSIDER: envio de planilha (aba Planilhas e bloco Buscar na planilha). O navegador lê o Excel ou CSV
// (spreadsheet.js), mostra as primeiras linhas e manda tudo em pedaços; a planilha nova só passa a valer
// quando o envio termina. pick(planilha) atualiza uma planilha existente; start(arquivo) já começa com
// um arquivo (solto na tela). Emite uploaded com a planilha pronta.
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BotDatasetsAPI from 'dashboard/api/outsider/botDatasets';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { loadIntegrations, useIntegrations } from './useIntegrations';
import {
  openSpreadsheet,
  toTable,
  SpreadsheetError,
  MAX_ROWS,
} from './spreadsheet';

const emit = defineEmits(['uploaded']);
const { t } = useI18n();
const store = useIntegrations();

const CHUNK_ROWS = 2000;
const CHUNK_CHARS = 1500000;

const fileInput = ref(null);
const uploadDialog = ref(null);
const upload = reactive({
  target: null,
  file: null,
  sheets: [],
  sheet: 0,
  table: null,
  name: '',
  error: '',
  reading: false,
  sending: false,
  sent: 0,
});

const spreadsheetError = error => {
  if (error instanceof SpreadsheetError) {
    return t(`OUTSIDER_TOOLS.BOT.DATASETS.ERRORS.${error.code}`, {
      max: MAX_ROWS.toLocaleString('pt-BR'),
      ...error.detail,
    });
  }
  return t('OUTSIDER_TOOLS.BOT.DATASETS.ERRORS.read_failed');
};

const readSheet = async index => {
  upload.sheet = index;
  upload.table = null;
  upload.error = '';
  upload.reading = true;
  try {
    upload.table = toTable(await upload.sheets[index].read());
  } catch (error) {
    upload.error = spreadsheetError(error);
  } finally {
    upload.reading = false;
  }
};

// o nome de uma planilha nova: o do arquivo, com (2), (3)... se já existir
const freeName = fileName => {
  const base = fileName.replace(/\.[^.]+$/, '').slice(0, 74) || 'Planilha';
  const taken = new Set(store.datasets.map(item => item.name));
  let name = base;
  for (let copy = 2; taken.has(name) && copy < 100; copy += 1) {
    name = `${base} (${copy})`;
  }
  return name;
};

const start = async (file, dataset = null) => {
  if (!file) return;
  Object.assign(upload, {
    target: dataset,
    file,
    sheets: [],
    sheet: 0,
    table: null,
    error: '',
    sent: 0,
    sending: false,
    name: dataset?.name || freeName(file.name),
  });
  uploadDialog.value?.open();
  upload.reading = true;
  try {
    upload.sheets = await openSpreadsheet(file);
    await readSheet(0);
  } catch (error) {
    upload.error = spreadsheetError(error);
    upload.reading = false;
  }
};

const pick = (dataset = null) => {
  upload.target = dataset;
  fileInput.value?.click();
};

const onFile = event => {
  const [file] = event.target.files || [];
  // eslint-disable-next-line no-param-reassign
  event.target.value = '';
  start(file, upload.target);
};

const chunks = rows => {
  const list = [];
  let current = [];
  let size = 0;
  rows.forEach(row => {
    const rowSize = row.reduce((sum, cell) => sum + cell.length + 4, 0);
    if (
      current.length &&
      (current.length >= CHUNK_ROWS || size + rowSize > CHUNK_CHARS)
    ) {
      list.push(current);
      current = [];
      size = 0;
    }
    current.push(row);
    size += rowSize;
  });
  if (current.length) list.push(current);
  return list;
};

const send = async () => {
  if (!upload.table || upload.sending || !upload.name.trim()) return;
  upload.sending = true;
  upload.error = '';
  upload.sent = 0;
  const { columns, rows } = upload.table;
  try {
    let dataset = upload.target;
    if (!dataset) {
      dataset = (await BotDatasetsAPI.create({ name: upload.name.trim() }))
        .data;
      upload.target = dataset;
    }
    let generation = 0;
    let offset = 0;
    // eslint-disable-next-line no-restricted-syntax
    for (const part of chunks(rows)) {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await BotDatasetsAPI.rows(dataset.id, {
        generation: generation || undefined,
        offset,
        columns,
        rows: part,
      });
      generation = data.generation;
      offset += part.length;
      upload.sent = offset;
    }
    await BotDatasetsAPI.finish(dataset.id, {
      generation,
      columns,
      file_name: upload.file.name,
    });
    await loadIntegrations(true);
    useAlert(
      t('OUTSIDER_TOOLS.BOT.DATASETS.UPLOADED', {
        name: dataset.name,
        count: rows.length.toLocaleString('pt-BR'),
      })
    );
    uploadDialog.value?.close();
    emit(
      'uploaded',
      store.datasets.find(item => item.id === dataset.id) || dataset
    );
  } catch (error) {
    upload.error =
      error?.response?.data?.message ||
      (error?.response?.data?.error
        ? t(`OUTSIDER_TOOLS.BOT.DATASETS.ERRORS.${error.response.data.error}`, {
            max: MAX_ROWS.toLocaleString('pt-BR'),
          })
        : t('OUTSIDER_TOOLS.BOT.DATASETS.ERRORS.upload_failed'));
  } finally {
    upload.sending = false;
  }
};

const progress = computed(() =>
  upload.table?.rows.length
    ? Math.round((upload.sent / upload.table.rows.length) * 100)
    : 0
);

defineExpose({ pick, start });
</script>

<template>
  <div class="contents">
    <input
      ref="fileInput"
      type="file"
      accept=".xlsx,.xlsm,.csv,.tsv,.txt"
      class="hidden"
      @change="onFile"
    />
    <Dialog
      ref="uploadDialog"
      :title="
        upload.target?.id
          ? t('OUTSIDER_TOOLS.BOT.DATASETS.REPLACE_TITLE', {
              name: upload.target.name,
            })
          : t('OUTSIDER_TOOLS.BOT.DATASETS.UPLOAD_TITLE')
      "
      width="3xl"
      overflow-y-auto
      :confirm-button-label="t('OUTSIDER_TOOLS.BOT.DATASETS.SEND')"
      :disable-confirm-button="!upload.table || !upload.name.trim()"
      :is-loading="upload.sending"
      @confirm="send"
    >
      <div class="flex flex-col gap-4">
        <span class="flex items-center gap-2 text-sm text-n-slate-12">
          <Icon icon="i-lucide-file-spreadsheet" class="size-4 shrink-0" />
          {{ upload.file?.name }}
        </span>
        <label v-if="!upload.target?.id" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.DATASETS.NAME') }}
          </span>
          <input
            v-model="upload.name"
            type="text"
            maxlength="80"
            class="!mb-0"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_TOOLS.BOT.DATASETS.NAME_HINT') }}
          </span>
        </label>
        <label v-if="upload.sheets.length > 1" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.DATASETS.SHEET') }}
          </span>
          <select
            :value="upload.sheet"
            class="!mb-0"
            :disabled="upload.sending"
            @change="readSheet(Number($event.target.value))"
          >
            <option
              v-for="(sheet, index) in upload.sheets"
              :key="index"
              :value="index"
            >
              {{ sheet.name }}
            </option>
          </select>
        </label>
        <div
          v-if="upload.reading"
          class="flex items-center gap-2 text-sm text-n-slate-11"
        >
          <Spinner class="size-4" />
          {{ t('OUTSIDER_TOOLS.BOT.DATASETS.READING') }}
        </div>
        <template v-else-if="upload.table">
          <span class="text-sm text-n-slate-12">
            {{
              t('OUTSIDER_TOOLS.BOT.DATASETS.READ_SUMMARY', {
                rows: upload.table.rows.length.toLocaleString('pt-BR'),
                columns: upload.table.columns.length,
              })
            }}
          </span>
          <div class="overflow-auto border rounded-lg max-h-72 border-n-weak">
            <table class="w-full text-xs">
              <thead class="sticky top-0 bg-n-solid-2">
                <tr>
                  <th
                    v-for="(column, index) in upload.table.columns"
                    :key="index"
                    class="px-2 py-1.5 font-medium text-left whitespace-nowrap text-n-slate-12"
                  >
                    {{ column }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(row, rowIndex) in upload.table.rows.slice(0, 8)"
                  :key="rowIndex"
                  class="border-t border-n-weak"
                >
                  <td
                    v-for="(cell, index) in row"
                    :key="index"
                    class="px-2 py-1 max-w-[14rem] truncate text-n-slate-11"
                  >
                    {{ cell }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <span class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_TOOLS.BOT.DATASETS.HEADER_HINT') }}
          </span>
        </template>
        <div v-if="upload.sending" class="flex flex-col gap-1">
          <div class="h-2 overflow-hidden rounded-full bg-n-alpha-2">
            <div
              class="h-full transition-all rounded-full bg-n-teal-9"
              :style="{ width: `${progress}%` }"
            />
          </div>
          <span class="text-xs text-n-slate-11">
            {{
              t('OUTSIDER_TOOLS.BOT.DATASETS.SENDING', {
                sent: upload.sent.toLocaleString('pt-BR'),
                total: upload.table.rows.length.toLocaleString('pt-BR'),
              })
            }}
          </span>
        </div>
        <p
          v-if="upload.error"
          class="flex items-start gap-1.5 mb-0 text-sm text-n-ruby-11"
        >
          <Icon icon="i-lucide-circle-x" class="size-4 mt-0.5 shrink-0" />
          {{ upload.error }}
        </p>
      </div>
    </Dialog>
  </div>
</template>
