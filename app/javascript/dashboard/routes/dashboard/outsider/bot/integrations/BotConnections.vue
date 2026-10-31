<script setup>
// OUTSIDER: aba Conexões da Automação por bot: os sistemas que os blocos chamam (APIs, Supabase, bancos
// PostgreSQL, GraphQL, webhooks e Nextcloud), com testar, editar e apagar. Senhas não aparecem aqui.
import { ref, reactive, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BotConnectionsAPI from 'dashboard/api/outsider/botConnections';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConnectionDialog from './ConnectionDialog.vue';
import { useIntegrations, loadIntegrations } from './useIntegrations';
import { errorText } from './integrationTypes';
import {
  PRESETS,
  connectionIcon,
  connectionAddress,
  authLabel,
  missingSecret,
} from './connections';

const { t, te } = useI18n();
const store = useIntegrations();
const dialog = ref(null);
const tests = reactive({});

// um webhook costuma aceitar só POST: o GET do Testar volta 404 ou 405, mas o servidor respondeu
const POST_ONLY = [404, 405];
const TEST_TONES = {
  ok: { box: 'bg-n-teal-3 text-n-teal-11', icon: 'i-lucide-circle-check' },
  warn: { box: 'bg-n-amber-3 text-n-amber-11', icon: 'i-lucide-circle-alert' },
  error: { box: 'bg-n-ruby-3 text-n-ruby-11', icon: 'i-lucide-circle-x' },
};

const testTone = (connection, result) => {
  if (result.ok) return 'ok';
  return connection.allow_write && POST_ONLY.includes(result.status)
    ? 'warn'
    : 'error';
};

const testText = (connection, result) => {
  if (!result.ok) {
    if (testTone(connection, result) === 'warn') {
      return t('OUTSIDER_TOOLS.BOT.CONNECTIONS.TEST_POST_ONLY', {
        status: result.status,
      });
    }
    const code = result.error || (result.status ? `http_${result.status}` : '');
    return errorText(code || 'connection_failed', t, te);
  }
  if (connection.kind === 'nextcloud') {
    const names = (result.entries || []).slice(0, 6).map(entry => entry.name);
    return t('OUTSIDER_TOOLS.BOT.CONNECTIONS.TEST_NEXTCLOUD', {
      folder: result.folder || '/',
      items:
        names.join(', ') || t('OUTSIDER_TOOLS.BOT.CONNECTIONS.EMPTY_FOLDER'),
    });
  }
  if (connection.kind === 'postgres') {
    return t('OUTSIDER_TOOLS.BOT.CONNECTIONS.TEST_POSTGRES', {
      database: result.database,
      user: result.user,
      version: result.version,
      ms: result.duration_ms,
    });
  }
  return t('OUTSIDER_TOOLS.BOT.CONNECTIONS.TEST_HTTP', {
    status: result.status,
    ms: result.duration_ms,
  });
};

const test = async connection => {
  tests[connection.id] = { loading: true };
  try {
    const { data } = await BotConnectionsAPI.test(connection.id);
    tests[connection.id] = {
      tone: testTone(connection, data),
      text: testText(connection, data),
      detail: data.ok ? '' : data.message || '',
      excerpt: data.excerpt || '',
    };
  } catch (error) {
    tests[connection.id] = {
      tone: 'error',
      text:
        error?.response?.data?.message ||
        t('OUTSIDER_TOOLS.BOT.CONNECTIONS.TEST_FAILED'),
    };
  }
};

const onSaved = async connection => {
  await loadIntegrations(true);
  if (connection?.id) test(connection);
};

const remove = async connection => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('OUTSIDER_TOOLS.BOT.CONNECTIONS.DELETE_CONFIRM', {
        name: connection.name,
      })
    )
  ) {
    return;
  }
  try {
    await BotConnectionsAPI.remove(connection.id);
  } catch (error) {
    const flows = error?.response?.data?.flows;
    if (error?.response?.data?.error !== 'in_use' || !flows) {
      useAlert(t('OUTSIDER_TOOLS.BOT.CONNECTIONS.DELETE_ERROR'));
      return;
    }
    const message = t('OUTSIDER_TOOLS.BOT.CONNECTIONS.DELETE_IN_USE', {
      flows: flows.map(flow => flow.name).join(', '),
    });
    // eslint-disable-next-line no-alert
    if (!window.confirm(message)) return;
    await BotConnectionsAPI.remove(connection.id, true);
  }
  await loadIntegrations(true);
  useAlert(t('OUTSIDER_TOOLS.BOT.CONNECTIONS.DELETED'));
};

const openCreate = (preset = '') => dialog.value?.open(null, preset);
const openEdit = connection => dialog.value?.open(connection);

onMounted(() => loadIntegrations(true));

defineExpose({ openCreate });
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-if="!store.loaded && store.loading"
      class="flex justify-center py-10"
    >
      <Spinner />
    </div>

    <!-- vazio: começa pelos tipos -->
    <div v-else-if="!store.connections.length" class="flex flex-col gap-4">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.EMPTY') }}
      </p>
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
        <button
          v-for="(item, id) in PRESETS"
          :key="id"
          type="button"
          class="flex items-start gap-3 p-3 text-left border rounded-xl border-n-weak bg-n-solid-1 hover:border-n-brand"
          @click="openCreate(id)"
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
    </div>

    <template v-else>
      <div
        v-for="connection in store.connections"
        :key="connection.id"
        class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-wrap items-start gap-3">
          <span
            class="flex items-center justify-center rounded-xl size-10 shrink-0 bg-n-violet-3 text-n-violet-11"
          >
            <Icon :icon="connectionIcon(connection)" class="size-5" />
          </span>
          <div class="flex flex-col flex-1 min-w-[12rem] gap-0.5">
            <span class="flex flex-wrap items-center gap-2">
              <span class="text-base font-medium text-n-slate-12">
                {{ connection.name }}
              </span>
              <span
                class="px-1.5 py-0.5 text-[11px] rounded-md"
                :class="
                  connection.allow_write
                    ? 'bg-n-amber-3 text-n-amber-11'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{
                  connection.allow_write
                    ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.WRITES')
                    : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.READ_ONLY')
                }}
              </span>
            </span>
            <span class="font-mono text-xs break-all text-n-slate-11">
              {{ connectionAddress(connection, t) }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                [
                  t(`OUTSIDER_TOOLS.BOT.CONNECTIONS.KINDS.${connection.kind}`),
                  authLabel(connection, t),
                  connection.flows?.length
                    ? t('OUTSIDER_TOOLS.BOT.CONNECTIONS.USED_IN', {
                        flows: connection.flows
                          .map(flow => flow.name)
                          .join(', '),
                      })
                    : t('OUTSIDER_TOOLS.BOT.CONNECTIONS.UNUSED'),
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </div>
          <div class="flex items-center gap-1">
            <Button
              :label="t('OUTSIDER_TOOLS.BOT.CONNECTIONS.TEST')"
              icon="i-lucide-activity"
              sm
              faded
              teal
              :is-loading="tests[connection.id]?.loading"
              @click="test(connection)"
            />
            <Button
              :label="t('OUTSIDER_TOOLS.BOT.LIST.EDIT')"
              icon="i-lucide-pencil"
              sm
              faded
              slate
              @click="openEdit(connection)"
            />
            <Button
              v-tooltip.top="t('OUTSIDER_TOOLS.BOT.LIST.DELETE')"
              icon="i-lucide-trash-2"
              sm
              ghost
              ruby
              @click="remove(connection)"
            />
          </div>
        </div>
        <p
          v-if="connection.secrets_unreadable"
          class="flex items-start gap-1.5 px-3 py-2 mb-0 text-xs rounded-lg bg-n-ruby-3 text-n-ruby-11"
        >
          <Icon icon="i-lucide-key-round" class="size-3.5 mt-px shrink-0" />
          {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.UNREADABLE') }}
        </p>
        <p
          v-else-if="missingSecret(connection)"
          class="flex items-start gap-1.5 px-3 py-2 mb-0 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
        >
          <Icon icon="i-lucide-key-round" class="size-3.5 mt-px shrink-0" />
          {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.MISSING_SECRET') }}
        </p>
        <div
          v-if="tests[connection.id] && !tests[connection.id].loading"
          class="flex flex-col gap-1 px-3 py-2 text-xs rounded-lg"
          :class="TEST_TONES[tests[connection.id].tone].box"
        >
          <span class="flex items-start gap-1.5">
            <Icon
              :icon="TEST_TONES[tests[connection.id].tone].icon"
              class="size-3.5 mt-px shrink-0"
            />
            {{ tests[connection.id].text }}
          </span>
          <span
            v-if="tests[connection.id].detail"
            class="font-mono break-all opacity-80"
          >
            {{ tests[connection.id].detail }}
          </span>
          <pre
            v-if="tests[connection.id].excerpt"
            class="p-2 mb-0 overflow-auto font-mono text-[11px] whitespace-pre-wrap rounded-md max-h-32 bg-n-solid-1 text-n-slate-11"
            >{{ tests[connection.id].excerpt }}</pre
          >
        </div>
      </div>
    </template>

    <p class="flex items-start gap-2 px-1 mt-2 mb-0 text-xs text-n-slate-10">
      <Icon icon="i-lucide-shield-check" class="size-4 shrink-0" />
      {{ t('OUTSIDER_TOOLS.BOT.CONNECTIONS.SECURITY_NOTE') }}
    </p>

    <ConnectionDialog ref="dialog" @saved="onSaved" />
  </div>
</template>
