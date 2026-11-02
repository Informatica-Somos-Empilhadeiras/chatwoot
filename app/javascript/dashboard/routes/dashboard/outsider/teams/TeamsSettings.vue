<script setup>
// OUTSIDER: Configurações > Microsoft Teams (Entrega 26, só administradores). O Chatwoot não tem canal do Teams (nem nas
// versões 4.17 a 4.19): cada robô do Teams ligado aqui vira uma caixa de entrada, e as conversas do Teams chegam nela
// como as dos outros canais. A tela mostra o passo a passo do Azure, o endereço de mensagens para colar no robô,
// confere as credenciais e baixa o pacote do aplicativo para enviar no Teams.
import { ref, reactive, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import TeamsAPI from 'dashboard/api/outsider/teams';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { downloadBlob } from '../voice/format';
import { formatDateTime } from '../crm/helpers';

const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const STEPS = ['AZURE', 'SECRET', 'ENDPOINT', 'CHANNEL', 'PACKAGE', 'AGENTS'];

const { t } = useI18n();
const route = useRoute();

const isLoading = ref(true);
const connections = ref([]);
const creating = ref(false);
const isSaving = ref(false);
// id da ligação com o formulário de credenciais aberto
const editing = ref(null);
const busy = reactive({});
const form = reactive({
  name: '',
  app_id: '',
  tenant_id: '',
  app_password: '',
});

const resetForm = () => {
  Object.assign(form, {
    name: '',
    app_id: '',
    tenant_id: '',
    app_password: '',
  });
};

const validForm = isNew =>
  GUID.test(form.app_id.trim()) &&
  (GUID.test(form.tenant_id.trim()) ||
    form.tenant_id.trim() === 'botframework.com') &&
  (!isNew || (form.name.trim() && form.app_password));

const message = error =>
  error?.response?.data?.message || t('OUTSIDER_TEAMS.ERRORS.GENERIC');

const load = async () => {
  try {
    const { data } = await TeamsAPI.get();
    connections.value = data.payload;
  } catch (error) {
    useAlert(message(error));
  } finally {
    isLoading.value = false;
  }
};

const create = async () => {
  if (!validForm(true)) return;
  isSaving.value = true;
  try {
    const { data } = await TeamsAPI.create({ ...form });
    connections.value = [...connections.value, data];
    creating.value = false;
    resetForm();
    useAlert(t('OUTSIDER_TEAMS.CREATED'));
  } catch (error) {
    useAlert(message(error));
  } finally {
    isSaving.value = false;
  }
};

const startEdit = connection => {
  editing.value = connection.id;
  Object.assign(form, {
    name: connection.inbox_name,
    app_id: connection.app_id,
    tenant_id: connection.tenant_id,
    app_password: '',
  });
};

const saveEdit = async connection => {
  if (!validForm(false)) return;
  isSaving.value = true;
  try {
    const { data } = await TeamsAPI.update(connection.id, {
      app_id: form.app_id,
      tenant_id: form.tenant_id,
      app_password: form.app_password,
    });
    Object.assign(connection, data);
    editing.value = null;
    resetForm();
    useAlert(t('OUTSIDER_TEAMS.SAVED'));
  } catch (error) {
    useAlert(message(error));
  } finally {
    isSaving.value = false;
  }
};

const run = async (connection, action) => {
  busy[`${connection.id}:${action}`] = true;
  try {
    if (action === 'test') {
      await TeamsAPI.test(connection.id);
      useAlert(t('OUTSIDER_TEAMS.TEST_OK'));
    } else if (action === 'manifest') {
      downloadBlob(await TeamsAPI.manifest(connection.id));
    } else if (action === 'delete') {
      // eslint-disable-next-line no-alert
      if (!window.confirm(t('OUTSIDER_TEAMS.DELETE_CONFIRM'))) return;
      await TeamsAPI.delete(connection.id);
      connections.value = connections.value.filter(
        item => item.id !== connection.id
      );
    }
  } catch (error) {
    useAlert(
      action === 'test'
        ? t('OUTSIDER_TEAMS.TEST_FAILED', {
            message: error?.response?.data?.message || '',
          })
        : message(error)
    );
  } finally {
    busy[`${connection.id}:${action}`] = false;
  }
};

const copy = async text => {
  await copyTextToClipboard(text);
  useAlert(t('OUTSIDER_TEAMS.COPIED'));
};

const inboxRoute = connection => ({
  name: 'settings_inbox_show',
  params: { accountId: route.params.accountId, inboxId: connection.inbox_id },
});

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('OUTSIDER_TEAMS.TITLE')"
        :description="t('OUTSIDER_TEAMS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            v-if="!creating"
            icon="i-lucide-plus"
            :label="t('OUTSIDER_TEAMS.CONNECT')"
            data-testid="teams-connect"
            @click="
              creating = true;
              editing = null;
              resetForm();
            "
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <!-- passo a passo -->
        <details
          class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          :open="!connections.length"
        >
          <summary
            class="flex items-center gap-2 text-sm font-medium cursor-pointer text-n-slate-12"
          >
            <Icon icon="i-lucide-list-ordered" class="size-4" />
            {{ t('OUTSIDER_TEAMS.GUIDE.TITLE') }}
          </summary>
          <ol
            class="flex flex-col gap-2 pl-5 mt-3 mb-0 text-sm list-decimal text-n-slate-11"
          >
            <li v-for="step in STEPS" :key="step">
              {{ t(`OUTSIDER_TEAMS.GUIDE.${step}`) }}
            </li>
          </ol>
        </details>

        <!-- ligar um robô -->
        <form
          v-if="creating"
          class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          data-testid="teams-form"
          @submit.prevent="create"
        >
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TEAMS.CONNECT') }}
          </h3>
          <Input
            v-model="form.name"
            :label="t('OUTSIDER_TEAMS.FIELDS.NAME')"
            :placeholder="t('OUTSIDER_TEAMS.FIELDS.NAME_PLACEHOLDER')"
          />
          <div class="grid gap-3 md:grid-cols-2">
            <Input
              v-model="form.app_id"
              :label="t('OUTSIDER_TEAMS.FIELDS.APP_ID')"
              placeholder="00000000-0000-0000-0000-000000000000"
            />
            <Input
              v-model="form.tenant_id"
              :label="t('OUTSIDER_TEAMS.FIELDS.TENANT_ID')"
              placeholder="00000000-0000-0000-0000-000000000000"
            />
          </div>
          <Input
            v-model="form.app_password"
            type="password"
            autocomplete="new-password"
            :label="t('OUTSIDER_TEAMS.FIELDS.APP_PASSWORD')"
          />
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_TEAMS.FIELDS.HELP') }}
          </p>
          <div class="flex justify-end gap-2">
            <Button
              type="button"
              slate
              faded
              :label="t('OUTSIDER_TEAMS.CANCEL')"
              @click="creating = false"
            />
            <Button
              type="submit"
              :label="t('OUTSIDER_TEAMS.SAVE')"
              :is-loading="isSaving"
              :disabled="!validForm(true)"
            />
          </div>
        </form>

        <p
          v-if="!connections.length && !creating"
          class="p-6 mb-0 text-sm text-center rounded-xl bg-n-alpha-1 text-n-slate-11"
        >
          {{ t('OUTSIDER_TEAMS.EMPTY') }}
        </p>

        <!-- robôs ligados -->
        <section
          v-for="connection in connections"
          :key="connection.id"
          class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
          data-testid="teams-connection"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="flex items-center gap-2 min-w-0">
              <span
                class="flex items-center justify-center rounded-lg size-8 bg-n-iris-3 text-n-iris-11 shrink-0"
              >
                <Icon icon="i-lucide-messages-square" class="size-4" />
              </span>
              <span class="flex flex-col min-w-0">
                <router-link
                  :to="inboxRoute(connection)"
                  class="text-sm font-medium truncate text-n-slate-12 hover:underline"
                >
                  {{ connection.inbox_name }}
                </router-link>
                <span class="text-xs text-n-slate-11">
                  {{
                    connection.last_activity_at
                      ? t('OUTSIDER_TEAMS.LAST_ACTIVITY', {
                          date: formatDateTime(connection.last_activity_at, t),
                        })
                      : t('OUTSIDER_TEAMS.NO_ACTIVITY')
                  }}
                </span>
              </span>
            </span>
            <span class="flex flex-wrap gap-1.5">
              <Button
                sm
                slate
                faded
                icon="i-lucide-shield-check"
                :label="t('OUTSIDER_TEAMS.TEST')"
                :is-loading="busy[`${connection.id}:test`]"
                @click="run(connection, 'test')"
              />
              <Button
                sm
                slate
                faded
                icon="i-lucide-package"
                :label="t('OUTSIDER_TEAMS.DOWNLOAD_PACKAGE')"
                :is-loading="busy[`${connection.id}:manifest`]"
                @click="run(connection, 'manifest')"
              />
              <Button
                sm
                slate
                ghost
                icon="i-lucide-key-round"
                :title="t('OUTSIDER_TEAMS.EDIT')"
                @click="startEdit(connection)"
              />
              <Button
                sm
                ruby
                ghost
                icon="i-lucide-unplug"
                :title="t('OUTSIDER_TEAMS.DELETE')"
                @click="run(connection, 'delete')"
              />
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('OUTSIDER_TEAMS.ENDPOINT') }}
            </span>
            <span class="flex items-center gap-2">
              <code
                class="flex-1 min-w-0 px-2 py-1.5 overflow-x-auto text-xs rounded-lg bg-n-alpha-2 text-n-slate-12 whitespace-nowrap"
              >
                {{ connection.messaging_endpoint }}
              </code>
              <Button
                sm
                slate
                ghost
                icon="i-lucide-copy"
                :title="t('OUTSIDER_TEAMS.COPY')"
                @click="copy(connection.messaging_endpoint)"
              />
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_TEAMS.ENDPOINT_HELP') }}
            </span>
          </div>
          <dl class="grid gap-2 mb-0 text-xs md:grid-cols-2">
            <div>
              <dt class="text-n-slate-11">
                {{ t('OUTSIDER_TEAMS.FIELDS.APP_ID') }}
              </dt>
              <dd class="mb-0 font-mono text-n-slate-12">
                {{ connection.app_id }}
              </dd>
            </div>
            <div>
              <dt class="text-n-slate-11">
                {{ t('OUTSIDER_TEAMS.FIELDS.TENANT_ID') }}
              </dt>
              <dd class="mb-0 font-mono text-n-slate-12">
                {{ connection.tenant_id }}
              </dd>
            </div>
          </dl>
          <form
            v-if="editing === connection.id"
            class="flex flex-col gap-3 pt-3 border-t border-n-weak"
            @submit.prevent="saveEdit(connection)"
          >
            <div class="grid gap-3 md:grid-cols-2">
              <Input
                v-model="form.app_id"
                :label="t('OUTSIDER_TEAMS.FIELDS.APP_ID')"
              />
              <Input
                v-model="form.tenant_id"
                :label="t('OUTSIDER_TEAMS.FIELDS.TENANT_ID')"
              />
            </div>
            <Input
              v-model="form.app_password"
              type="password"
              autocomplete="new-password"
              :label="t('OUTSIDER_TEAMS.FIELDS.APP_PASSWORD')"
              :placeholder="t('OUTSIDER_TEAMS.FIELDS.KEEP_PASSWORD')"
            />
            <div class="flex justify-end gap-2">
              <Button
                type="button"
                slate
                faded
                :label="t('OUTSIDER_TEAMS.CANCEL')"
                @click="editing = null"
              />
              <Button
                type="submit"
                :label="t('OUTSIDER_TEAMS.SAVE')"
                :is-loading="isSaving"
                :disabled="!validForm(false)"
              />
            </div>
          </form>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>
