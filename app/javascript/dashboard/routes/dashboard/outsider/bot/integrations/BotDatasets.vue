<script setup>
// OUTSIDER: aba Planilhas da Automação por bot: as planilhas enviadas (aqui ou no próprio bloco Buscar na
// planilha, pelo SpreadsheetUpload). Ver mostra e procura nas linhas; Atualizar troca o conteúdo mantendo o
// nome (os blocos continuam ligados).
import { ref, reactive, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import BotDatasetsAPI from 'dashboard/api/outsider/botDatasets';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SpreadsheetUpload from './SpreadsheetUpload.vue';
import { useIntegrations, loadIntegrations } from './useIntegrations';

const { t } = useI18n();
const store = useIntegrations();

// ---------- envio (SpreadsheetUpload) ----------
const uploader = ref(null);
const pickFile = (dataset = null) => uploader.value?.pick(dataset);

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
    <SpreadsheetUpload ref="uploader" />

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
