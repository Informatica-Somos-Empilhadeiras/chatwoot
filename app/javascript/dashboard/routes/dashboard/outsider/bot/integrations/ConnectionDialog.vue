<script setup>
// OUTSIDER: cadastrar ou editar uma conexão do bot. Começa escolhendo o tipo (API de um sistema, Supabase,
// banco PostgreSQL, GraphQL, webhook do n8n/Make/Zapier ou Nextcloud), que já deixa o formulário certo.
// Senha e chave nunca voltam do servidor: em branco mantém a que está salva.
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BotConnectionsAPI from 'dashboard/api/outsider/botConnections';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import KeyValueRows from './KeyValueRows.vue';
import { PRESETS } from './connections';

const emit = defineEmits(['saved']);
const { t } = useI18n();

// exemplos nos campos (técnicos, iguais em todo idioma)
const EXAMPLES = {
  supabase: 'https://abcdefghij.supabase.co',
  folder: '/Documentos',
  tokenUrl: 'https://auth.sistema.com.br/oauth/token',
  testPath: '/status',
};
const AUTH_TYPES = [
  'none',
  'header',
  'query',
  'bearer',
  'basic',
  'oauth2',
  'headers',
];
const SSL_MODES = ['', 'require', 'prefer', 'disable', 'verify-full'];

const dialogRef = ref(null);
const connection = ref(null);
const preset = ref('');
const isSaving = ref(false);
const errorMessage = ref('');

const blank = () => ({
  name: '',
  kind: 'http',
  base_url: '',
  auth_type: 'none',
  timeout_seconds: 10,
  allow_write: false,
  header_name: 'X-API-Key',
  query_param: 'api_key',
  username: '',
  token_url: '',
  client_id: '',
  scope: '',
  client_auth: 'body',
  root_folder: '/',
  test_path: '',
  sslmode: '',
  headers: [],
  api_key: '',
  token: '',
  password: '',
  client_secret: '',
  secret_headers: [],
  connection_string: '',
  supabase_url: '',
  supabase_key: '',
});
const form = reactive(blank());

const isNew = computed(() => !connection.value);
const choosing = computed(() => isNew.value && !preset.value);
const saved = key => !!connection.value?.secrets_set?.[key];
const savedPlaceholder = key =>
  saved(key) ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SAVED_SECRET') : '';
const title = computed(() => {
  if (!isNew.value) {
    return t('OUTSIDER_TOOLS.BOT.CONNECTIONS.EDIT_TITLE', {
      name: connection.value.name,
    });
  }
  return preset.value
    ? t(`OUTSIDER_TOOLS.BOT.CONNECTIONS.PRESETS.${preset.value}.TITLE`)
    : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.NEW_TITLE');
});

const pgParts = computed(() => {
  const match = String(connection.value?.base_url || '').match(
    /^postgresql:\/\/(.+):(\d+)\/(.+)$/
  );
  return match ? { host: match[1], port: match[2], database: match[3] } : null;
});

const choose = id => {
  preset.value = id;
  Object.assign(form, blank(), PRESETS[id].form);
};

const open = (item = null, presetId = '') => {
  connection.value = item;
  errorMessage.value = '';
  Object.assign(form, blank());
  preset.value = '';
  if (item) {
    const settings = item.settings || {};
    Object.assign(form, {
      name: item.name,
      kind: item.kind,
      base_url: item.kind === 'postgres' ? '' : item.base_url,
      auth_type: item.auth_type,
      timeout_seconds: item.timeout_seconds,
      allow_write: item.allow_write,
      header_name: settings.header_name || 'X-API-Key',
      query_param: settings.query_param || 'api_key',
      username: settings.username || '',
      token_url: settings.token_url || '',
      client_id: settings.client_id || '',
      scope: settings.scope || '',
      client_auth: settings.client_auth || 'body',
      root_folder: settings.root_folder || '/',
      test_path: settings.test_path || '',
      sslmode: settings.sslmode || '',
      headers: Object.entries(item.headers || {}).map(([key, value]) => ({
        key,
        value,
      })),
      secret_headers: (item.secret_headers || []).map(name => ({
        name,
        value: '',
        saved: true,
      })),
    });
  } else if (presetId && PRESETS[presetId]) {
    choose(presetId);
  }
  dialogRef.value?.open();
};

const secretHeaderRows = computed({
  get: () =>
    form.secret_headers.map(item => ({ key: item.name, value: item.value })),
  set: rows => {
    form.secret_headers = rows.map(row => ({
      name: row.key,
      value: row.value,
      saved: form.secret_headers.some(
        item => item.saved && item.name === row.key
      ),
    }));
  },
});

// https://abcd.supabase.co ou já com /rest/v1
const supabaseBase = url => {
  const clean = String(url || '')
    .trim()
    .replace(/\/+$/, '');
  return /\/rest\/v1$/.test(clean) ? clean : `${clean}/rest/v1`;
};

const httpSecrets = () => {
  switch (form.auth_type) {
    case 'header':
    case 'query':
      return form.api_key ? { api_key: form.api_key } : null;
    case 'bearer':
      return form.token ? { token: form.token } : null;
    case 'basic':
      return form.password ? { password: form.password } : null;
    case 'oauth2':
      return form.client_secret ? { client_secret: form.client_secret } : null;
    case 'headers':
      return {
        headers: form.secret_headers
          .filter(item => item.name.trim())
          .map(item => ({ name: item.name.trim(), value: item.value })),
      };
    default:
      return null;
  }
};

const payload = () => {
  const data = {
    name: form.name.trim(),
    kind: form.kind,
    timeout_seconds: Number(form.timeout_seconds) || 10,
    allow_write: form.allow_write,
  };
  if (form.kind === 'postgres') {
    if (form.connection_string.trim()) {
      data.connection_string = form.connection_string.trim();
    }
    if (form.sslmode) data.settings = { sslmode: form.sslmode };
    return data;
  }
  if (form.kind === 'nextcloud') {
    data.base_url = form.base_url.trim();
    data.settings = {
      username: form.username.trim(),
      root_folder: form.root_folder || '/',
    };
    if (form.password) data.secrets = { password: form.password };
    return data;
  }
  if (isNew.value && preset.value === 'supabase') {
    const key = form.supabase_key.trim();
    return {
      ...data,
      base_url: supabaseBase(form.supabase_url),
      auth_type: 'headers',
      headers: [],
      secrets: {
        headers: [
          { name: 'apikey', value: key },
          { name: 'Authorization', value: key ? `Bearer ${key}` : '' },
        ],
      },
    };
  }
  data.base_url = form.base_url.trim();
  data.auth_type = form.auth_type;
  data.headers = form.headers.filter(item => item.key.trim());
  data.settings = {
    header_name: form.header_name,
    query_param: form.query_param,
    username: form.username,
    token_url: form.token_url,
    client_id: form.client_id,
    scope: form.scope,
    client_auth: form.client_auth,
    test_path: form.test_path,
  };
  const secrets = httpSecrets();
  if (secrets) data.secrets = secrets;
  return data;
};

const missing = computed(() => {
  if (!form.name.trim()) return true;
  if (form.kind === 'postgres')
    return isNew.value && !form.connection_string.trim();
  if (isNew.value && preset.value === 'supabase') {
    return !form.supabase_url.trim() || !form.supabase_key.trim();
  }
  return !form.base_url.trim();
});

const save = async () => {
  if (missing.value || isSaving.value) return;
  isSaving.value = true;
  errorMessage.value = '';
  try {
    const { data } = isNew.value
      ? await BotConnectionsAPI.create(payload())
      : await BotConnectionsAPI.update(connection.value.id, payload());
    useAlert(t('OUTSIDER_TOOLS.BOT.CONNECTIONS.SAVED'));
    emit('saved', data);
    dialogRef.value?.close();
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.message ||
      t('OUTSIDER_TOOLS.BOT.CONNECTIONS.SAVE_ERROR');
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    width="2xl"
    overflow-y-auto
    :show-confirm-button="!choosing"
    :confirm-button-label="t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SAVE')"
    :disable-confirm-button="missing"
    :is-loading="isSaving"
    @confirm="save"
  >
    <!-- 1. tipo de conexão -->
    <div v-if="choosing" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <button
        v-for="(item, id) in PRESETS"
        :key="id"
        type="button"
        class="flex items-start gap-3 p-3 text-left border rounded-xl border-n-weak hover:border-n-brand hover:bg-n-brand/5"
        @click="choose(id)"
      >
        <span
          class="flex items-center justify-center rounded-lg size-9 shrink-0 bg-n-violet-3 text-n-violet-11"
        >
          <Icon :icon="item.icon" class="size-5" />
        </span>
        <span class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`OUTSIDER_TOOLS.BOT.CONNECTIONS.PRESETS.${id}.TITLE`) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t(`OUTSIDER_TOOLS.BOT.CONNECTIONS.PRESETS.${id}.HINT`) }}
          </span>
        </span>
      </button>
    </div>

    <!-- 2. formulário -->
    <div v-else class="flex flex-col gap-4">
      <p
        v-if="preset"
        class="flex items-start gap-2 px-3 py-2 mb-0 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11"
      >
        <Icon icon="i-lucide-info" class="size-4 shrink-0" />
        {{ t(`OUTSIDER_TOOLS.BOT.CONNECTIONS.PRESETS.${preset}.HELP`) }}
      </p>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.NAME') }}
        </span>
        <input
          v-model="form.name"
          type="text"
          maxlength="80"
          class="!mb-0"
          :placeholder="
            t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.NAME_PLACEHOLDER')
          "
        />
      </label>

      <!-- banco PostgreSQL -->
      <template v-if="form.kind === 'postgres'">
        <div
          v-if="pgParts"
          class="flex flex-col gap-0.5 px-3 py-2 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11"
        >
          <span>
            {{
              t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.PG_CURRENT', {
                host: pgParts.host,
                port: pgParts.port,
                database: pgParts.database,
                user: connection?.settings?.username || '—',
              })
            }}
          </span>
        </div>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{
              isNew
                ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CONNECTION_STRING_NEW')
                : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CONNECTION_STRING')
            }}
          </span>
          <textarea
            v-model="form.connection_string"
            rows="2"
            spellcheck="false"
            autocomplete="off"
            class="!mb-0 font-mono !text-xs"
            placeholder="postgresql://postgres.abcd:SENHA@aws-0-sa-east-1.pooler.supabase.com:5432/postgres"
          />
          <span class="text-xs text-n-slate-10">
            {{
              t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CONNECTION_STRING_HINT', {
                example: 'postgresql://usuario:senha@servidor:5432/banco',
              })
            }}
          </span>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SSL_MODE') }}
          </span>
          <select v-model="form.sslmode" class="!mb-0">
            <option v-for="mode in SSL_MODES" :key="mode" :value="mode">
              {{
                t(`OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SSL.${mode || 'auto'}`)
              }}
            </option>
          </select>
        </label>
      </template>

      <!-- Supabase (API REST) -->
      <template v-else-if="isNew && preset === 'supabase'">
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SUPABASE_URL') }}
          </span>
          <input
            v-model="form.supabase_url"
            type="text"
            class="!mb-0 font-mono !text-xs"
            :placeholder="EXAMPLES.supabase"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SUPABASE_KEY') }}
          </span>
          <input
            v-model="form.supabase_key"
            type="password"
            autocomplete="new-password"
            class="!mb-0 font-mono !text-xs"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SUPABASE_KEY_HINT') }}
          </span>
        </label>
      </template>

      <!-- Nextcloud e APIs -->
      <template v-else>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{
              form.kind === 'nextcloud'
                ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.NEXTCLOUD_URL')
                : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.BASE_URL')
            }}
          </span>
          <input
            v-model="form.base_url"
            type="text"
            class="!mb-0 font-mono !text-xs"
            :placeholder="
              preset === 'webhook'
                ? 'https://n8n.suaempresa.com.br/webhook/abc123'
                : 'https://erp.suaempresa.com.br/api/v1'
            "
          />
          <span class="text-xs text-n-slate-10">
            {{
              form.kind === 'nextcloud'
                ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.NEXTCLOUD_URL_HINT')
                : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.BASE_URL_HINT')
            }}
          </span>
        </label>

        <template v-if="form.kind === 'nextcloud'">
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.USERNAME') }}
              </span>
              <input
                v-model="form.username"
                type="text"
                autocomplete="off"
                class="!mb-0"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.APP_PASSWORD') }}
              </span>
              <input
                v-model="form.password"
                type="password"
                autocomplete="new-password"
                class="!mb-0"
                :placeholder="savedPlaceholder('password')"
              />
            </label>
          </div>
          <span class="-mt-2 text-xs text-n-slate-10">
            {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.APP_PASSWORD_HINT') }}
          </span>
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.ROOT_FOLDER') }}
            </span>
            <input
              v-model="form.root_folder"
              type="text"
              class="!mb-0 font-mono !text-xs"
              :placeholder="EXAMPLES.folder"
            />
            <span class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.ROOT_FOLDER_HINT') }}
            </span>
          </label>
        </template>

        <template v-else>
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.AUTH') }}
            </span>
            <select v-model="form.auth_type" class="!mb-0">
              <option v-for="type in AUTH_TYPES" :key="type" :value="type">
                {{ t(`OUTSIDER_TOOLS.BOT.CONNECTIONS.AUTH.${type}`) }}
              </option>
            </select>
          </label>
          <div
            v-if="form.auth_type !== 'none'"
            class="flex flex-col gap-3 p-3 border rounded-xl border-n-weak"
          >
            <template v-if="['header', 'query'].includes(form.auth_type)">
              <label class="flex flex-col gap-1">
                <span class="text-sm text-n-slate-12">
                  {{
                    form.auth_type === 'header'
                      ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.HEADER_NAME')
                      : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.QUERY_PARAM')
                  }}
                </span>
                <input
                  v-if="form.auth_type === 'header'"
                  v-model="form.header_name"
                  type="text"
                  class="!mb-0 font-mono !text-xs"
                />
                <input
                  v-else
                  v-model="form.query_param"
                  type="text"
                  class="!mb-0 font-mono !text-xs"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-sm text-n-slate-12">
                  {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.API_KEY') }}
                </span>
                <input
                  v-model="form.api_key"
                  type="password"
                  autocomplete="new-password"
                  class="!mb-0 font-mono !text-xs"
                  :placeholder="savedPlaceholder('api_key')"
                />
              </label>
            </template>
            <label
              v-else-if="form.auth_type === 'bearer'"
              class="flex flex-col gap-1"
            >
              <span class="text-sm text-n-slate-12">
                {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.TOKEN') }}
              </span>
              <input
                v-model="form.token"
                type="password"
                autocomplete="new-password"
                class="!mb-0 font-mono !text-xs"
                :placeholder="savedPlaceholder('token')"
              />
            </label>
            <div
              v-else-if="form.auth_type === 'basic'"
              class="grid grid-cols-1 gap-3 sm:grid-cols-2"
            >
              <label class="flex flex-col gap-1">
                <span class="text-sm text-n-slate-12">
                  {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.USERNAME') }}
                </span>
                <input
                  v-model="form.username"
                  type="text"
                  autocomplete="off"
                  class="!mb-0"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-sm text-n-slate-12">
                  {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.PASSWORD') }}
                </span>
                <input
                  v-model="form.password"
                  type="password"
                  autocomplete="new-password"
                  class="!mb-0"
                  :placeholder="savedPlaceholder('password')"
                />
              </label>
            </div>
            <template v-else-if="form.auth_type === 'oauth2'">
              <label class="flex flex-col gap-1">
                <span class="text-sm text-n-slate-12">
                  {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.TOKEN_URL') }}
                </span>
                <input
                  v-model="form.token_url"
                  type="text"
                  class="!mb-0 font-mono !text-xs"
                  :placeholder="EXAMPLES.tokenUrl"
                />
              </label>
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <label class="flex flex-col gap-1">
                  <span class="text-sm text-n-slate-12">
                    {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CLIENT_ID') }}
                  </span>
                  <input
                    v-model="form.client_id"
                    type="text"
                    class="!mb-0 font-mono !text-xs"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="text-sm text-n-slate-12">
                    {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CLIENT_SECRET') }}
                  </span>
                  <input
                    v-model="form.client_secret"
                    type="password"
                    autocomplete="new-password"
                    class="!mb-0 font-mono !text-xs"
                    :placeholder="savedPlaceholder('client_secret')"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="text-sm text-n-slate-12">
                    {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SCOPE') }}
                  </span>
                  <input
                    v-model="form.scope"
                    type="text"
                    class="!mb-0 font-mono !text-xs"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="text-sm text-n-slate-12">
                    {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CLIENT_AUTH') }}
                  </span>
                  <select v-model="form.client_auth" class="!mb-0">
                    <option value="body">
                      {{
                        t(
                          'OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CLIENT_AUTH_BODY'
                        )
                      }}
                    </option>
                    <option value="basic">
                      {{
                        t(
                          'OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.CLIENT_AUTH_BASIC'
                        )
                      }}
                    </option>
                  </select>
                </label>
              </div>
            </template>
            <template v-else-if="form.auth_type === 'headers'">
              <span class="text-xs text-n-slate-11">
                {{
                  t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SECRET_HEADERS_HINT')
                }}
              </span>
              <KeyValueRows
                v-model="secretHeaderRows"
                :max="5"
                key-placeholder="apikey"
                :value-placeholder="
                  t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.SECRET_HEADER_VALUE')
                "
              />
            </template>
          </div>

          <details>
            <summary
              class="text-sm font-medium cursor-pointer select-none text-n-slate-12"
            >
              {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.MORE') }}
            </summary>
            <div class="flex flex-col gap-3 pt-3">
              <div class="flex flex-col gap-1">
                <span class="text-sm text-n-slate-12">
                  {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.HEADERS') }}
                </span>
                <KeyValueRows
                  v-model="form.headers"
                  key-placeholder="Accept"
                  value-placeholder="application/json"
                />
              </div>
              <label class="flex flex-col gap-1">
                <span class="text-sm text-n-slate-12">
                  {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.TEST_PATH') }}
                </span>
                <input
                  v-model="form.test_path"
                  type="text"
                  class="!mb-0 font-mono !text-xs"
                  :placeholder="EXAMPLES.testPath"
                />
                <span class="text-xs text-n-slate-10">
                  {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.TEST_PATH_HINT') }}
                </span>
              </label>
            </div>
          </details>
        </template>
      </template>

      <label
        class="flex items-center justify-between gap-3 text-sm text-n-slate-12"
      >
        {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.TIMEOUT') }}
        <input
          v-model.number="form.timeout_seconds"
          type="number"
          min="1"
          max="30"
          class="!mb-0 !h-8 !w-20 text-sm"
        />
      </label>

      <label
        v-if="form.kind !== 'nextcloud'"
        class="flex items-start justify-between gap-3 p-3 border rounded-xl"
        :class="
          form.allow_write ? 'border-n-amber-7 bg-n-amber-2' : 'border-n-weak'
        "
      >
        <span class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.ALLOW_WRITE') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              form.kind === 'postgres'
                ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.ALLOW_WRITE_DB')
                : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.ALLOW_WRITE_HINT')
            }}
          </span>
        </span>
        <Switch v-model="form.allow_write" />
      </label>

      <p
        v-if="errorMessage"
        class="flex items-start gap-1.5 mb-0 text-sm text-n-ruby-11"
      >
        <Icon icon="i-lucide-circle-x" class="size-4 mt-0.5 shrink-0" />
        {{ errorMessage }}
      </p>
      <Button
        v-if="isNew"
        :label="t('OUTSIDER_TOOLS.BOT.CONNECTIONS.FORM.BACK')"
        icon="i-lucide-arrow-left"
        xs
        ghost
        slate
        class="self-start"
        type="button"
        @click="preset = ''"
      />
    </div>
  </Dialog>
</template>
