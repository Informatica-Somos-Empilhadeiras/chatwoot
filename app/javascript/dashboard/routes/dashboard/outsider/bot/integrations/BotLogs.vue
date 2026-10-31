<script setup>
// OUTSIDER: aba Registro da Automação por bot: cada chamada que o bot fez a outro sistema (API, banco,
// Nextcloud), cada busca em planilha e cada teste de conexão dos últimos 7 dias, com filtros, tempo,
// resultado e o erro por extenso. Senhas e chaves nunca chegam aqui (o servidor já grava sem elas).
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import BotLogsAPI from 'dashboard/api/outsider/botLogs';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { useIntegrations, loadIntegrations } from './useIntegrations';
import { errorText } from './integrationTypes';

defineProps({
  flows: { type: Array, default: () => [] },
});

const KIND_ICONS = {
  api: 'i-lucide-plug-zap',
  db_query: 'i-lucide-database',
  sheet: 'i-lucide-sheet',
  doc_search: 'i-lucide-file-search',
  doc_send: 'i-lucide-file-up',
  file_send: 'i-lucide-paperclip',
  test: 'i-lucide-activity',
};
const KINDS = Object.keys(KIND_ICONS);
const STATUSES = ['ok', 'not_found', 'error'];
const STATUS_TONES = {
  ok: 'bg-n-teal-3 text-n-teal-11',
  not_found: 'bg-n-amber-3 text-n-amber-11',
  error: 'bg-n-ruby-3 text-n-ruby-11',
};
// campos curtos do detalhe, nesta ordem; os longos (SQL, corpo, resposta) vão em caixas
const FIELDS = [
  'method',
  'url',
  'path',
  'dataset',
  'column',
  'value',
  'folder',
  'query',
  'found',
  'files',
  'file',
  'mode',
  'params',
  'rows',
  'affected',
  'cached',
];
const BOXES = ['sql', 'body', 'response'];

const { t, te, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useIntegrations();

const filters = reactive({
  status: '',
  kind: '',
  connection_id: '',
  flow_id: '',
});
const logs = ref([]);
const nextBeforeId = ref(null);
const loading = ref(false);
const loadingMore = ref(false);
const failed = ref(false);
const expanded = reactive({});
let request = 0;

const hasFilters = computed(() =>
  Object.values(filters).some(value => value !== '')
);

const fetchPage = async beforeId => {
  const params = Object.fromEntries(
    Object.entries(filters).filter(([, value]) => value !== '')
  );
  if (beforeId) params.before_id = beforeId;
  const { data } = await BotLogsAPI.list(params);
  return data;
};

const reload = async () => {
  request += 1;
  const current = request;
  loading.value = true;
  failed.value = false;
  try {
    const data = await fetchPage(null);
    if (current !== request) return;
    logs.value = data.payload;
    nextBeforeId.value = data.next_before_id;
  } catch {
    if (current === request) failed.value = true;
  } finally {
    if (current === request) loading.value = false;
  }
};

const loadMore = async () => {
  if (!nextBeforeId.value || loadingMore.value) return;
  const current = request;
  loadingMore.value = true;
  try {
    const data = await fetchPage(nextBeforeId.value);
    if (current !== request) return;
    logs.value = [...logs.value, ...data.payload];
    nextBeforeId.value = data.next_before_id;
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BOT.LOGS.LOAD_ERROR'));
  } finally {
    loadingMore.value = false;
  }
};

const clearFilters = () => {
  Object.keys(filters).forEach(key => {
    filters[key] = '';
  });
};

const dateFormat = computed(() => {
  const options = {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  };
  try {
    return new Intl.DateTimeFormat(locale.value.replace('_', '-'), options);
  } catch {
    return new Intl.DateTimeFormat(undefined, options);
  }
});
const when = log => dateFormat.value.format(new Date(log.created_at * 1000));

const duration = ms => {
  if (ms === null || ms === undefined) return '';
  if (ms < 1000) return `${ms} ms`;
  const seconds = (ms / 1000).toLocaleString(locale.value.replace('_', '-'), {
    maximumFractionDigits: 1,
  });
  return `${seconds} s`;
};

const cut = (text, size = 90) => {
  const value = String(text ?? '')
    .replace(/\s+/g, ' ')
    .trim();
  return value.length > size ? `${value.slice(0, size - 1)}…` : value;
};

// o que foi chamado, numa linha
const headline = log => {
  const detail = log.detail || {};
  const key = 'OUTSIDER_TOOLS.BOT.LOGS.HEADLINES';
  switch (log.kind) {
    case 'api':
      return cut(
        [detail.method, detail.path || detail.url].filter(Boolean).join(' ')
      );
    case 'db_query':
      return cut(detail.sql);
    case 'sheet':
      return t(`${key}.sheet`, {
        dataset: detail.dataset || '',
        column: detail.column || '',
        value: cut(detail.value, 40),
      });
    case 'doc_search':
      return detail.query
        ? t(`${key}.doc_search`, {
            query: cut(detail.query, 40),
            folder: detail.folder || '/',
          })
        : t(`${key}.doc_search_latest`, { folder: detail.folder || '/' });
    case 'doc_send':
    case 'file_send':
      return detail.file
        ? t(`${key}.doc_send`, { file: detail.file })
        : t(`${key}.doc_send_empty`);
    default:
      return cut(detail.url || log.connection?.name || '');
  }
};

const problem = log => {
  const detail = log.detail || {};
  if (log.status === 'ok') return '';
  if (log.status === 'not_found' && !detail.error) {
    return t('OUTSIDER_TOOLS.BOT.LOGS.NOTHING_FOUND');
  }
  const code =
    detail.error || (log.http_status ? `http_${log.http_status}` : '');
  return code ? errorText(code, t, te) : '';
};

const fieldValue = (key, value) => {
  if (key === 'cached') return t('OUTSIDER_TOOLS.BOT.LOGS.YES');
  if (
    key === 'mode' &&
    te(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND_MODES.${value}`)
  ) {
    return t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.SEND_MODES.${value}`);
  }
  if (Array.isArray(value)) return value.join(', ') || '—';
  if (value === null || value === undefined || value === '') return '—';
  return String(value);
};

const fields = log =>
  FIELDS.filter(
    key => log.detail?.[key] !== undefined && log.detail?.[key] !== null
  ).map(key => ({ key, value: fieldValue(key, log.detail[key]) }));

const boxes = log =>
  BOXES.filter(key => log.detail?.[key]).map(key => {
    const raw = log.detail[key];
    let text = String(raw);
    try {
      const parsed = JSON.parse(text);
      if (parsed && typeof parsed === 'object') {
        text = JSON.stringify(parsed, null, 2);
      }
    } catch {
      // não é JSON (ou foi cortado no meio): mostra como veio
    }
    return { key, text };
  });

const conversationLink = log =>
  frontendURL(
    `accounts/${route.params.accountId}/conversations/${log.conversation_display_id}`
  );

const flowLink = log =>
  router.resolve({
    name: 'outsider_bot_flow_editor',
    params: { flowId: log.flow.id },
    query: log.node_id ? { node: log.node_id } : {},
  }).href;

const toggle = log => {
  expanded[log.id] = !expanded[log.id];
};

watch(filters, reload);

onMounted(() => {
  loadIntegrations();
  reload();
});

defineExpose({ reload });
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-end gap-2">
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.STATUS') }}
        <select v-model="filters.status" class="!mb-0 !w-40">
          <option value="">
            {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.ALL') }}
          </option>
          <option v-for="status in STATUSES" :key="status" :value="status">
            {{ t(`OUTSIDER_TOOLS.BOT.LOGS.STATUSES.${status}`) }}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.KIND') }}
        <select v-model="filters.kind" class="!mb-0 !w-44">
          <option value="">
            {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.ALL') }}
          </option>
          <option v-for="kind in KINDS" :key="kind" :value="kind">
            {{ t(`OUTSIDER_TOOLS.BOT.LOGS.KINDS.${kind}`) }}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.CONNECTION') }}
        <select v-model="filters.connection_id" class="!mb-0 !w-48">
          <option value="">
            {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.ALL') }}
          </option>
          <option
            v-for="connection in store.connections"
            :key="connection.id"
            :value="String(connection.id)"
          >
            {{ connection.name }}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.FLOW') }}
        <select v-model="filters.flow_id" class="!mb-0 !w-48">
          <option value="">
            {{ t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.ALL') }}
          </option>
          <option v-for="flow in flows" :key="flow.id" :value="String(flow.id)">
            {{ flow.name }}
          </option>
        </select>
      </label>
      <Button
        v-if="hasFilters"
        :label="t('OUTSIDER_TOOLS.BOT.LOGS.FILTERS.CLEAR')"
        icon="i-lucide-x"
        sm
        ghost
        slate
        class="mb-0.5"
        @click="clearFilters"
      />
    </div>

    <div v-if="loading && !logs.length" class="flex justify-center py-10">
      <Spinner />
    </div>

    <div
      v-else-if="failed"
      class="flex flex-col items-center gap-3 px-4 py-8 text-sm text-center border rounded-xl border-n-weak text-n-slate-11"
    >
      {{ t('OUTSIDER_TOOLS.BOT.LOGS.LOAD_ERROR') }}
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.LOGS.RETRY')"
        icon="i-lucide-refresh-cw"
        sm
        faded
        slate
        @click="reload"
      />
    </div>

    <p
      v-else-if="!logs.length"
      class="px-4 py-8 mb-0 text-sm text-center border border-dashed rounded-xl border-n-weak text-n-slate-11"
    >
      {{
        hasFilters
          ? t('OUTSIDER_TOOLS.BOT.LOGS.EMPTY_FILTERED')
          : t('OUTSIDER_TOOLS.BOT.LOGS.EMPTY')
      }}
    </p>

    <div
      v-else
      class="flex flex-col overflow-hidden border divide-y rounded-xl border-n-weak divide-n-weak bg-n-solid-1"
      :class="{ 'opacity-60': loading }"
    >
      <div v-for="log in logs" :key="log.id" class="flex flex-col">
        <button
          type="button"
          class="flex items-start gap-3 px-3 py-2.5 text-left hover:bg-n-alpha-1"
          :aria-expanded="!!expanded[log.id]"
          @click="toggle(log)"
        >
          <span
            class="flex items-center justify-center mt-0.5 rounded-lg size-8 shrink-0"
            :class="STATUS_TONES[log.status] || STATUS_TONES.error"
          >
            <Icon
              :icon="KIND_ICONS[log.kind] || 'i-lucide-plug'"
              class="size-4"
            />
          </span>
          <span class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="flex flex-wrap items-center gap-x-2 gap-y-0.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t(`OUTSIDER_TOOLS.BOT.LOGS.KINDS.${log.kind}`) }}
              </span>
              <span
                class="px-1.5 py-px text-[11px] rounded-md"
                :class="STATUS_TONES[log.status] || STATUS_TONES.error"
              >
                {{ t(`OUTSIDER_TOOLS.BOT.LOGS.STATUSES.${log.status}`) }}
                <template v-if="log.http_status">
                  · {{ log.http_status }}
                </template>
              </span>
              <span
                v-if="log.detail?.test"
                class="px-1.5 py-px text-[11px] rounded-md bg-n-alpha-2 text-n-slate-11"
              >
                {{ t('OUTSIDER_TOOLS.BOT.LOGS.TEST_BADGE') }}
              </span>
              <span
                v-if="log.detail?.cached"
                class="px-1.5 py-px text-[11px] rounded-md bg-n-blue-3 text-n-blue-11"
              >
                {{ t('OUTSIDER_TOOLS.BOT.LOGS.CACHED_BADGE') }}
              </span>
            </span>
            <span class="font-mono text-xs break-all text-n-slate-11">
              {{ headline(log) }}
            </span>
            <span
              v-if="problem(log)"
              class="text-xs"
              :class="
                log.status === 'not_found'
                  ? 'text-n-amber-11'
                  : 'text-n-ruby-11'
              "
            >
              {{ problem(log) }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                [
                  log.flow?.name ||
                    (log.flow ? t('OUTSIDER_TOOLS.BOT.LOGS.DELETED_FLOW') : ''),
                  log.connection?.name ||
                    (log.connection
                      ? t('OUTSIDER_TOOLS.BOT.LOGS.DELETED_CONNECTION')
                      : ''),
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </span>
          <span
            class="flex flex-col items-end gap-0.5 shrink-0 text-xs text-n-slate-11"
          >
            <span class="tabular-nums">{{ when(log) }}</span>
            <span
              v-if="log.duration_ms !== null"
              class="tabular-nums text-n-slate-10"
            >
              {{ duration(log.duration_ms) }}
            </span>
          </span>
          <Icon
            :icon="
              expanded[log.id] ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
            class="mt-1 size-4 shrink-0 text-n-slate-10"
          />
        </button>

        <div
          v-if="expanded[log.id]"
          class="flex flex-col gap-2 px-3 pb-3 pl-14 text-xs text-n-slate-12"
        >
          <div class="flex flex-wrap gap-2">
            <a
              v-if="log.conversation_display_id"
              :href="conversationLink(log)"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
            >
              <Icon icon="i-lucide-message-circle" class="size-3.5" />
              {{
                t('OUTSIDER_TOOLS.BOT.LOGS.OPEN_CONVERSATION', {
                  id: log.conversation_display_id,
                })
              }}
            </a>
            <a
              v-if="log.flow?.name"
              :href="flowLink(log)"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
            >
              <Icon icon="i-lucide-workflow" class="size-3.5" />
              {{ t('OUTSIDER_TOOLS.BOT.LOGS.OPEN_BLOCK') }}
            </a>
          </div>
          <p
            v-if="log.detail?.message"
            class="mb-0 font-mono break-all text-n-ruby-11"
          >
            {{ log.detail.message }}
          </p>
          <dl
            v-if="fields(log).length"
            class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 mb-0"
          >
            <template v-for="field in fields(log)" :key="field.key">
              <dt class="text-n-slate-10">
                {{ t(`OUTSIDER_TOOLS.BOT.LOGS.DETAIL.${field.key}`) }}
              </dt>
              <dd class="mb-0 font-mono break-all">{{ field.value }}</dd>
            </template>
          </dl>
          <div
            v-for="box in boxes(log)"
            :key="box.key"
            class="flex flex-col gap-1"
          >
            <span class="text-n-slate-10">
              {{ t(`OUTSIDER_TOOLS.BOT.LOGS.DETAIL.${box.key}`) }}
            </span>
            <pre
              class="p-2 mb-0 overflow-auto font-mono text-[11px] whitespace-pre-wrap break-all rounded-md max-h-60 bg-n-alpha-1 text-n-slate-12"
              >{{ box.text }}</pre
            >
          </div>
        </div>
      </div>
    </div>

    <div v-if="nextBeforeId && logs.length" class="flex justify-center">
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.LOGS.MORE')"
        icon="i-lucide-chevrons-down"
        sm
        faded
        slate
        :is-loading="loadingMore"
        @click="loadMore"
      />
    </div>

    <p class="flex items-start gap-2 px-1 mt-2 mb-0 text-xs text-n-slate-10">
      <Icon icon="i-lucide-shield-check" class="size-4 shrink-0" />
      {{ t('OUTSIDER_TOOLS.BOT.LOGS.RETENTION_NOTE') }}
    </p>
  </div>
</template>
