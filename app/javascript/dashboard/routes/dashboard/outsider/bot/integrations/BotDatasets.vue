<script setup>
// OUTSIDER: aba Planilhas da Automação por bot. O navegador lê o Excel ou CSV (spreadsheet.js), mostra as
// primeiras linhas e manda tudo em pedaços; a planilha nova só passa a valer quando o envio termina.
// Ver mostra e procura nas linhas; Atualizar troca o conteúdo mantendo o nome (os blocos continuam ligados).
import { ref, reactive, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import BotDatasetsAPI from 'dashboard/api/outsider/botDatasets';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useIntegrations, loadIntegrations } from './useIntegrations';
import {
  openSpreadsheet,
  toTable,
  SpreadsheetError,
  MAX_ROWS,
} from './spreadsheet';

const { t } = useI18n();
const store = useIntegrations();

const CHUNK_ROWS = 2000;
const CHUNK_CHARS = 1500000;

// ---------- envio ----------
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

const pickFile = (dataset = null) => {
  upload.target = dataset;
  fileInput.value?.click();
};

const onFile = async event => {
  const [file] = event.target.files || [];
  // eslint-disable-next-line no-param-reassign
  event.target.value = '';
  if (!file) return;
  Object.assign(upload, {
    file,
    sheets: [],
    sheet: 0,
    table: null,
    error: '',
    sent: 0,
    sending: false,
    name: upload.target?.name || file.name.replace(/\.[^.]+$/, '').slice(0, 80),
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

// ---------- ver e procurar ----------
const viewDialog = ref(null);
const view = reactive({
  dataset: null,
  rows: [],
  matches: 0,
  q: '',
  loading: false,
});

const loadRows = async () => {
  if (!view.dataset) return;
  view.loading = true;
  try {
    const { data } = await BotDatasetsAPI.search(view.dataset.id, view.q);
    view.rows = data.rows;
    view.matches = data.matches;
  } catch {
    view.rows = [];
  } finally {
    view.loading = false;
  }
};
const searchRows = debounce(loadRows, 350);
const openView = dataset => {
  Object.assign(view, { dataset, rows: [], matches: 0, q: '' });
  viewDialog.value?.open();
  loadRows();
};

// ---------- renomear e apagar ----------
const rename = async dataset => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(
    t('OUTSIDER_TOOLS.BOT.DATASETS.RENAME_PROMPT'),
    dataset.name
  );
  if (!name || !name.trim() || name.trim() === dataset.name) return;
  try {
    await BotDatasetsAPI.update(dataset.id, { name: name.trim() });
    await loadIntegrations(true);
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('OUTSIDER_TOOLS.BOT.DATASETS.SAVE_ERROR')
    );
  }
};

const remove = async dataset => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('OUTSIDER_TOOLS.BOT.DATASETS.DELETE_CONFIRM', { name: dataset.name })
    )
  ) {
    return;
  }
  try {
    await BotDatasetsAPI.delete(dataset.id);
    await loadIntegrations(true);
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BOT.DATASETS.SAVE_ERROR'));
  }
};

const formatDate = seconds =>
  new Date(seconds * 1000).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

onMounted(() => loadIntegrations(true));

defineExpose({ pickFile: () => pickFile(null) });
</script>

<template>
  <div class="flex flex-col gap-3">
    <input
      ref="fileInput"
      type="file"
      accept=".xlsx,.xlsm,.csv,.tsv,.txt"
      class="hidden"
      @change="onFile"
    />

    <div
      v-if="!store.loaded && store.loading"
      class="flex justify-center py-10"
    >
      <Spinner />
    </div>
    <button
      v-else-if="!store.datasets.length"
      type="button"
      class="flex flex-col items-center gap-2 p-10 text-center border-2 border-dashed rounded-xl border-n-weak hover:border-n-brand"
      @click="pickFile(null)"
    >
      <Icon icon="i-lucide-sheet" class="size-8 text-n-teal-10" />
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.DATASETS.EMPTY_TITLE') }}
      </span>
      <span class="max-w-md text-xs text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.DATASETS.EMPTY') }}
      </span>
    </button>

    <template v-else>
      <div
        v-for="dataset in store.datasets"
        :key="dataset.id"
        class="flex flex-wrap items-start gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <span
          class="flex items-center justify-center rounded-xl size-10 shrink-0 bg-n-teal-3 text-n-teal-11"
        >
          <Icon icon="i-lucide-sheet" class="size-5" />
        </span>
        <div class="flex flex-col flex-1 min-w-[12rem] gap-1">
          <span class="text-base font-medium text-n-slate-12">
            {{ dataset.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              t('OUTSIDER_TOOLS.BOT.DATASETS.SUMMARY', {
                rows: dataset.rows_count.toLocaleString('pt-BR'),
                columns: dataset.columns.length,
                file: dataset.file_name || '—',
                date: formatDate(dataset.updated_at),
              })
            }}
          </span>
          <div class="flex flex-wrap gap-1">
            <span
              v-for="column in dataset.columns.slice(0, 10)"
              :key="column.key"
              class="px-1.5 py-0.5 text-[11px] rounded-md bg-n-alpha-2 text-n-slate-11"
            >
              {{ column.label }}
            </span>
            <span
              v-if="dataset.columns.length > 10"
              class="px-1.5 py-0.5 text-[11px] text-n-slate-10"
            >
              +{{ dataset.columns.length - 10 }}
            </span>
          </div>
          <span v-if="!dataset.rows_count" class="text-xs text-n-amber-11">
            {{ t('OUTSIDER_TOOLS.BOT.DATASETS.NO_ROWS') }}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <Button
            :label="t('OUTSIDER_TOOLS.BOT.DATASETS.VIEW')"
            icon="i-lucide-eye"
            sm
            faded
            slate
            :disabled="!dataset.rows_count"
            @click="openView(dataset)"
          />
          <Button
            :label="t('OUTSIDER_TOOLS.BOT.DATASETS.REPLACE')"
            icon="i-lucide-refresh-cw"
            sm
            faded
            teal
            @click="pickFile(dataset)"
          />
          <Button
            v-tooltip.top="t('OUTSIDER_TOOLS.BOT.DATASETS.RENAME')"
            icon="i-lucide-pencil"
            sm
            ghost
            slate
            @click="rename(dataset)"
          />
          <Button
            v-tooltip.top="t('OUTSIDER_TOOLS.BOT.LIST.DELETE')"
            icon="i-lucide-trash-2"
            sm
            ghost
            ruby
            @click="remove(dataset)"
          />
        </div>
      </div>
    </template>

    <p class="flex items-start gap-2 px-1 mt-2 mb-0 text-xs text-n-slate-10">
      <Icon icon="i-lucide-info" class="size-4 shrink-0" />
      {{ t('OUTSIDER_TOOLS.BOT.DATASETS.HINT') }}
    </p>

    <!-- enviar -->
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

    <!-- ver -->
    <Dialog
      ref="viewDialog"
      :title="view.dataset?.name || ''"
      width="3xl"
      overflow-y-auto
      :show-confirm-button="false"
      :cancel-button-label="t('OUTSIDER_TOOLS.BOT.DATASETS.CLOSE')"
    >
      <div v-if="view.dataset" class="flex flex-col gap-3">
        <input
          v-model="view.q"
          type="text"
          class="!mb-0"
          :placeholder="t('OUTSIDER_TOOLS.BOT.DATASETS.SEARCH')"
          @input="searchRows"
          @keydown.enter.prevent
        />
        <span class="text-xs text-n-slate-11">
          {{
            view.q
              ? t('OUTSIDER_TOOLS.BOT.DATASETS.MATCHES', {
                  count: view.matches.toLocaleString('pt-BR'),
                })
              : t('OUTSIDER_TOOLS.BOT.DATASETS.FIRST_ROWS', {
                  shown: view.rows.length,
                  count: view.matches.toLocaleString('pt-BR'),
                })
          }}
        </span>
        <div
          class="overflow-auto border rounded-lg max-h-[26rem] border-n-weak"
        >
          <table class="w-full text-xs">
            <thead class="sticky top-0 bg-n-solid-2">
              <tr>
                <th
                  v-for="column in view.dataset.columns"
                  :key="column.key"
                  class="px-2 py-1.5 font-medium text-left whitespace-nowrap text-n-slate-12"
                >
                  {{ column.label }}
                  <span
                    class="block font-mono font-normal text-[10px] text-n-slate-10"
                  >
                    {{ column.key }}
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(row, index) in view.rows"
                :key="index"
                class="border-t border-n-weak"
              >
                <td
                  v-for="column in view.dataset.columns"
                  :key="column.key"
                  class="px-2 py-1 max-w-[14rem] truncate text-n-slate-11"
                  :title="row[column.key]"
                >
                  {{ row[column.key] }}
                </td>
              </tr>
            </tbody>
          </table>
          <div v-if="view.loading" class="flex justify-center py-4">
            <Spinner />
          </div>
        </div>
      </div>
    </Dialog>
  </div>
</template>
