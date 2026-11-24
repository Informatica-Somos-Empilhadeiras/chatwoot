<script setup>
// OUTSIDER: Configurações > Google (bloco Google dos Aplicativos: Gmail, Agenda e Drive).
//   Todos: "Minha conta Google": entrar com a conta Google, ver o que está liberado, entrar de novo, desconectar.
//   Administradores: o aplicativo da empresa no Google Cloud (ID do cliente e chave secreta, cadastro único do TI, com o
//   passo a passo) e quem está conectado (só a situação; e-mails, eventos e arquivos ficam com cada pessoa).
// A volta do login do Google chega aqui (?google_oauth[...]) e é terminada com a sessão da pessoa.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import AppsAPI from 'dashboard/api/outsider/apps';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import AppLogo from './AppLogo.vue';
import { loadAppsSummary } from './appsStore';
import { errorText } from './appsErrors';
import './apps.css';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const APPS = [
  { key: 'mail', logo: 'gmail', name: 'OUTSIDER_APPS.GMAIL' },
  { key: 'calendar', logo: 'gcalendar', name: 'OUTSIDER_APPS.CALENDAR' },
  { key: 'drive', logo: 'gdrive', name: 'OUTSIDER_APPS.GDRIVE' },
];

const isLoading = ref(true);
const isFinishing = ref(false);
const isGoing = ref(false);
const isSaving = ref(false);
const info = ref(null);
const editing = ref(false);
const showGuide = ref(false);
const form = ref({ client_id: '', client_secret: '' });

const isAdmin = computed(() => !!info.value?.admin);
const me = computed(() => info.value?.me || null);
const missing = computed(() =>
  me.value ? APPS.filter(app => !me.value[app.key]) : []
);

const load = async () => {
  try {
    const { data } = await AppsAPI.googleAccount();
    info.value = data;
    editing.value = data.admin && !data.configured;
    showGuide.value = data.admin && !data.configured;
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isLoading.value = false;
  }
};

const oauthParams = () => {
  const found = {};
  ['code', 'state', 'error'].forEach(key => {
    const value = route.query[`google_oauth[${key}]`];
    if (value) found[key] = value;
  });
  return found.state || found.error ? found : null;
};

// volta do Google: termina o login e limpa o endereço
const finishOAuth = async params => {
  isFinishing.value = true;
  router.replace({ query: {} });
  try {
    await AppsAPI.googleFinish(params);
    useAlert(t('OUTSIDER_APPS.GSET.CONNECTED_DONE'));
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isFinishing.value = false;
  }
};

const refresh = async () => {
  await load();
  loadAppsSummary(route.params.accountId);
};

const connect = async () => {
  isGoing.value = true;
  try {
    const { data } = await AppsAPI.googleAuthorize();
    window.location.assign(data.url);
  } catch (error) {
    isGoing.value = false;
    useAlert(errorText(error, t));
  }
};

const disconnect = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('OUTSIDER_APPS.GSET.DISCONNECT_CONFIRM'))) return;
  try {
    await AppsAPI.googleDisconnect();
    useAlert(t('OUTSIDER_APPS.GSET.DISCONNECTED'));
    refresh();
  } catch (error) {
    useAlert(errorText(error, t));
  }
};

const removeLink = async link => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('OUTSIDER_APPS.GSET.REMOVE_CONFIRM', { name: link.user || link.email })
    )
  )
    return;
  try {
    await AppsAPI.googleRemoveLink(link.id);
    refresh();
  } catch (error) {
    useAlert(errorText(error, t));
  }
};

const startEdit = () => {
  form.value = {
    client_id: info.value?.app?.client_id || '',
    client_secret: '',
  };
  editing.value = true;
};

const canSave = computed(
  () =>
    /\.apps\.googleusercontent\.com$/.test(form.value.client_id.trim()) &&
    (info.value?.configured || form.value.client_secret.trim())
);

const save = async () => {
  isSaving.value = true;
  try {
    await AppsAPI.saveGoogleApp(form.value);
    useAlert(t('OUTSIDER_APPS.GSET.APP_SAVED'));
    editing.value = false;
    refresh();
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isSaving.value = false;
  }
};

const copy = async value => {
  await copyTextToClipboard(value);
  useAlert(t('OUTSIDER_APPS.GSET.COPIED'));
};

const short = value =>
  value && value.length > 24
    ? `${value.slice(0, 12)}…${value.slice(-27)}`
    : value || '';

const when = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';

const statusText = status =>
  ({
    active: t('OUTSIDER_APPS.STATUS.ACTIVE'),
    reconnect: t('OUTSIDER_APPS.STATUS.RECONNECT'),
  })[status] || t('OUTSIDER_APPS.STATUS.DISCONNECTED');

onMounted(async () => {
  const params = oauthParams();
  if (params) await finishOAuth(params);
  await refresh();
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading || isFinishing" class="oapps">
    <template #header>
      <BaseSettingsHeader
        :title="t('OUTSIDER_APPS.GSET.TITLE')"
        :description="t('OUTSIDER_APPS.GSET.DESCRIPTION')"
      >
        <template #title>
          <h1 class="flex items-center gap-2.5 text-heading-1 text-n-slate-12">
            <AppLogo name="google" :size="26" />
            {{ t('OUTSIDER_APPS.GSET.TITLE') }}
          </h1>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div v-if="info" class="flex flex-col gap-4 pb-8" data-google-settings>
        <!-- minha conta -->
        <section
          class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
          data-google-me
        >
          <div class="flex flex-wrap items-center gap-2">
            <Icon icon="i-lucide-user-round" class="size-5 text-n-slate-12" />
            <h3 class="mb-0 text-[15px] font-semibold text-n-slate-12">
              {{ t('OUTSIDER_APPS.GSET.ME_TITLE') }}
            </h3>
            <span
              v-if="me"
              class="px-2 py-0.5 text-xs font-semibold rounded-full"
              :class="
                me.status === 'active'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{ statusText(me.status) }}
            </span>
          </div>

          <p v-if="!info.configured" class="mt-2 mb-0 text-sm text-n-slate-11">
            {{
              isAdmin
                ? t('OUTSIDER_APPS.GSET.NOT_CONFIGURED_ADMIN')
                : t('OUTSIDER_APPS.GSET.NOT_CONFIGURED')
            }}
          </p>

          <template v-else-if="!me">
            <p class="mt-1 mb-3 text-sm text-n-slate-11">
              {{ t('OUTSIDER_APPS.GSET.CONNECT_TEXT') }}
            </p>
            <div class="flex flex-wrap gap-2 mb-3">
              <span
                v-for="app in APPS"
                :key="app.key"
                class="flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
              >
                <AppLogo :name="app.logo" :size="14" />
                {{ t(app.name) }}
              </span>
            </div>
            <button
              type="button"
              class="oa-btn"
              :disabled="isGoing"
              data-google-connect
              @click="connect"
            >
              <AppLogo name="google" :size="16" />
              {{ t('OUTSIDER_APPS.GSET.CONNECT_BUTTON') }}
            </button>
            <p class="mt-3 mb-0 text-xs text-n-slate-10">
              {{ t('OUTSIDER_APPS.GSET.UNVERIFIED_HINT') }}
            </p>
          </template>

          <template v-else>
            <div class="flex flex-wrap items-center gap-3 mt-3">
              <span
                class="grid text-sm font-semibold rounded-full size-10 place-items-center bg-n-alpha-2 text-n-slate-12 shrink-0"
              >
                {{ (me.name || me.email || '?').slice(0, 1).toUpperCase() }}
              </span>
              <span class="min-w-0">
                <b class="block text-sm truncate text-n-slate-12">
                  {{ me.name || me.email }}
                </b>
                <span class="block text-xs truncate text-n-slate-11">
                  {{ me.email }}
                </span>
              </span>
              <span class="flex flex-wrap gap-2 ml-auto">
                <button type="button" class="oa-ghost" @click="connect">
                  <Icon icon="i-lucide-refresh-cw" class="size-4" />
                  {{ t('OUTSIDER_APPS.GATE.RECONNECT_BUTTON') }}
                </button>
                <button
                  type="button"
                  class="oa-ghost is-danger"
                  data-google-disconnect
                  @click="disconnect"
                >
                  <Icon icon="i-lucide-log-out" class="size-4" />
                  {{ t('OUTSIDER_APPS.GSET.DISCONNECT') }}
                </button>
              </span>
            </div>
            <div class="flex flex-wrap gap-2 mt-3">
              <span
                v-for="app in APPS"
                :key="app.key"
                class="flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full"
                :class="
                  me[app.key]
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-alpha-2 text-n-slate-10 line-through'
                "
              >
                <AppLogo :name="app.logo" :size="14" />
                {{ t(app.name) }}
              </span>
            </div>
            <p
              v-if="me.status === 'reconnect'"
              class="flex items-start gap-2 p-2.5 mt-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
            >
              <Icon
                icon="i-lucide-triangle-alert"
                class="size-4 mt-0.5 shrink-0"
              />
              {{ t('OUTSIDER_APPS.GSET.RECONNECT_TEXT') }}
            </p>
            <p
              v-else-if="missing.length"
              class="flex items-start gap-2 p-2.5 mt-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
            >
              <Icon icon="i-lucide-info" class="size-4 mt-0.5 shrink-0" />
              {{
                t('OUTSIDER_APPS.GSET.MISSING', {
                  apps: missing.map(app => t(app.name)).join(', '),
                })
              }}
            </p>
          </template>
        </section>

        <!-- aplicativo da empresa (TI) -->
        <section
          v-if="isAdmin"
          class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
          data-google-app
        >
          <div class="flex flex-wrap items-center gap-2">
            <Icon icon="i-lucide-shield-check" class="size-5 text-n-slate-12" />
            <h3 class="mb-0 text-[15px] font-semibold text-n-slate-12">
              {{ t('OUTSIDER_APPS.GSET.APP_TITLE') }}
            </h3>
            <span
              class="px-2 py-0.5 text-xs font-semibold rounded-full"
              :class="
                info.configured
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{
                info.configured
                  ? t('OUTSIDER_APPS.GSET.APP_READY')
                  : t('OUTSIDER_APPS.GSET.APP_MISSING')
              }}
            </span>
            <span class="ml-auto text-xs text-n-slate-10">
              {{ t('OUTSIDER_APPS.GSET.ADMINS_ONLY') }}
            </span>
          </div>
          <p class="mt-1 mb-3 text-sm text-n-slate-11">
            {{ t('OUTSIDER_APPS.GSET.APP_INTRO') }}
          </p>

          <div
            v-if="!info.public_https"
            class="flex items-start gap-2 p-2.5 mb-3 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
          >
            <Icon
              icon="i-lucide-triangle-alert"
              class="size-4 mt-0.5 shrink-0"
            />
            <span>{{ t('OUTSIDER_APPS.GSET.NOT_PUBLIC') }}</span>
          </div>

          <div class="grid gap-3 mb-3 md:grid-cols-2">
            <div
              v-for="field in [
                { label: 'OUTSIDER_APPS.GSET.ORIGIN', value: info.origin },
                {
                  label: 'OUTSIDER_APPS.GSET.REDIRECT',
                  value: info.redirect_uri,
                },
              ]"
              :key="field.label"
              class="min-w-0"
            >
              <span class="block mb-1 text-sm font-medium text-n-slate-12">
                {{ t(field.label) }}
              </span>
              <span
                class="flex items-center gap-2 px-3 py-2 font-mono text-xs border rounded-lg border-n-weak bg-n-surface-1 text-n-slate-12"
              >
                <span class="flex-1 min-w-0 truncate">{{ field.value }}</span>
                <button
                  type="button"
                  class="text-n-slate-11 hover:text-n-slate-12 shrink-0"
                  :title="t('OUTSIDER_APPS.GSET.COPY')"
                  @click="copy(field.value)"
                >
                  <Icon icon="i-lucide-copy" class="size-4" />
                </button>
              </span>
            </div>
          </div>

          <form
            v-if="editing"
            class="flex flex-col gap-3"
            @submit.prevent="save"
          >
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_APPS.GSET.CLIENT_ID') }}
              <input
                v-model="form.client_id"
                type="text"
                autocomplete="off"
                spellcheck="false"
                class="!mt-1 !mb-0 !w-full font-mono !text-sm"
                :placeholder="t('OUTSIDER_APPS.GSET.CLIENT_ID_PLACEHOLDER')"
                data-google-client-id
              />
            </label>
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_APPS.GSET.CLIENT_SECRET') }}
              <input
                v-model="form.client_secret"
                type="password"
                autocomplete="new-password"
                class="!mt-1 !mb-0 !w-full !text-sm"
                :placeholder="
                  info.configured
                    ? t('OUTSIDER_APPS.GSET.SECRET_KEEP')
                    : 'GOCSPX-…'
                "
                data-google-client-secret
              />
            </label>
            <div class="flex justify-end gap-2">
              <Button
                v-if="info.configured"
                type="button"
                sm
                slate
                faded
                :label="t('OUTSIDER_APPS.GSET.CANCEL')"
                @click="editing = false"
              />
              <Button
                type="submit"
                sm
                :label="t('OUTSIDER_APPS.GSET.SAVE_APP')"
                :is-loading="isSaving"
                :disabled="!canSave"
              />
            </div>
          </form>
          <div v-else class="flex flex-wrap items-end gap-3">
            <div class="flex-1 min-w-0">
              <span class="block mb-1 text-sm font-medium text-n-slate-12">
                {{ t('OUTSIDER_APPS.GSET.CLIENT_ID') }}
              </span>
              <span
                class="block px-3 py-2 font-mono text-xs truncate border rounded-lg border-n-weak bg-n-surface-1 text-n-slate-12"
              >
                {{ short(info.app?.client_id) }}
              </span>
            </div>
            <button type="button" class="oa-ghost" @click="startEdit">
              <Icon icon="i-lucide-pencil" class="size-4" />
              {{ t('OUTSIDER_APPS.GSET.EDIT_APP') }}
            </button>
          </div>

          <button
            type="button"
            class="flex items-center gap-1.5 mt-4 text-sm font-medium text-n-slate-12"
            @click="showGuide = !showGuide"
          >
            <Icon
              :icon="
                showGuide ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'
              "
              class="size-4"
            />
            {{ t('OUTSIDER_APPS.GSET.GUIDE_TITLE') }}
          </button>
          <ol
            v-if="showGuide"
            class="flex flex-col gap-1.5 pl-5 mt-2 mb-0 text-sm list-decimal text-n-slate-11"
          >
            <li v-for="step in 7" :key="step">
              {{ t(`OUTSIDER_APPS.GSET.GUIDE_${step}`) }}
            </li>
          </ol>
        </section>

        <!-- quem está conectado -->
        <section
          v-if="isAdmin && info.links.length"
          class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
          data-google-people
        >
          <div class="flex items-center gap-2 mb-2">
            <Icon icon="i-lucide-users" class="size-5 text-n-slate-12" />
            <h3 class="mb-0 text-[15px] font-semibold text-n-slate-12">
              {{
                t('OUTSIDER_APPS.GSET.PEOPLE_TITLE', {
                  count: info.links.length,
                })
              }}
            </h3>
          </div>
          <ul class="flex flex-col mb-0 divide-y divide-n-weak">
            <li
              v-for="link in info.links"
              :key="link.id"
              class="flex flex-wrap items-center gap-x-3 gap-y-1 py-2.5"
            >
              <span class="min-w-0 flex-1">
                <b class="block text-sm truncate text-n-slate-12">
                  {{ link.user || link.name }}
                </b>
                <span class="block text-xs truncate text-n-slate-11">
                  {{ link.email }}
                  <template v-if="link.checked_at">
                    ·
                    {{
                      t('OUTSIDER_APPS.GSET.CHECKED', {
                        when: when(link.checked_at),
                      })
                    }}
                  </template>
                </span>
              </span>
              <span class="flex gap-1">
                <AppLogo
                  v-for="app in APPS"
                  :key="app.key"
                  :name="app.logo"
                  :size="16"
                  :class="{ 'opacity-25 grayscale': !link[app.key] }"
                />
              </span>
              <span
                class="px-2 py-0.5 text-xs font-semibold rounded-full"
                :class="
                  link.status === 'active'
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-amber-3 text-n-amber-11'
                "
              >
                {{ statusText(link.status) }}
              </span>
              <button
                type="button"
                class="oa-ghost is-danger"
                :title="t('OUTSIDER_APPS.GSET.REMOVE')"
                @click="removeLink(link)"
              >
                <Icon icon="i-lucide-user-x" class="size-4" />
              </button>
            </li>
          </ul>
        </section>

        <div
          class="flex items-start gap-2.5 p-3 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
        >
          <Icon icon="i-lucide-eye-off" class="size-4 mt-0.5 shrink-0" />
          <span>
            <b class="text-n-slate-12">{{
              t('OUTSIDER_APPS.GSET.PRIVACY_TITLE')
            }}</b>
            {{ t('OUTSIDER_APPS.GSET.PRIVACY') }}
          </span>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
