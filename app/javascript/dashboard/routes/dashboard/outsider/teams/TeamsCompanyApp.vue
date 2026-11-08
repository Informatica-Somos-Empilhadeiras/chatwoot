<script setup>
// OUTSIDER: "Aplicativo da empresa" em Configurações > Microsoft Teams (só administradores). O TI registra uma vez o
// aplicativo no Microsoft Entra ID (ID do aplicativo, ID do locatário e um segredo) e dá o consentimento pela empresa;
// depois cada colaborador só clica em "Entrar com a conta Microsoft". O segredo nunca volta para a tela.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { errorText } from './helpers';

const props = defineProps({ info: { type: Object, required: true } });
const emit = defineEmits(['changed']);

const { t } = useI18n();
const editing = ref(!props.info.configured);
const showGuide = ref(!props.info.configured);
const isSaving = ref(false);
const isGoing = ref(false);
const form = ref({ client_id: '', tenant_id: '', client_secret: '' });

const status = computed(() => {
  if (!props.info.configured) return 'missing';
  return props.info.consent_granted_at ? 'ready' : 'consent';
});

const consentDate = computed(() => {
  const iso = props.info.consent_granted_at;
  return iso ? new Date(iso).toLocaleDateString('pt-BR') : '';
});

// "3f2a9c1e-…-77b0": o bastante para o TI conferir sem ocupar a tela
const short = value =>
  value && value.length > 14 ? `${value.slice(0, 8)}-…-${value.slice(-4)}` : value || '';

const startEdit = () => {
  form.value = {
    client_id: props.info.app?.client_id || '',
    tenant_id: props.info.app?.tenant_id || '',
    client_secret: '',
  };
  editing.value = true;
};

const save = async () => {
  isSaving.value = true;
  try {
    await TeamsGraphAPI.saveApp(form.value);
    useAlert(t('OUTSIDER_TEAMS_GRAPH.APP_SAVED'));
    editing.value = false;
    emit('changed');
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isSaving.value = false;
  }
};

const consent = async () => {
  isGoing.value = true;
  try {
    const { data } = await TeamsGraphAPI.consentUrl();
    window.location.assign(data.url);
  } catch (error) {
    isGoing.value = false;
    useAlert(errorText(error, t));
  }
};

const copy = async value => {
  await copyTextToClipboard(value);
  useAlert(t('OUTSIDER_TEAMS_GRAPH.COPIED'));
};

const canSave = computed(
  () =>
    form.value.client_id.trim() &&
    form.value.tenant_id.trim() &&
    (props.info.configured || form.value.client_secret.trim())
);
</script>

<template>
  <section
    class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
    data-testid="teams-company-app"
  >
    <div class="flex flex-wrap items-center gap-2">
      <Icon icon="i-lucide-shield-check" class="size-5 text-n-slate-12" />
      <h3 class="mb-0 text-[15px] font-semibold text-n-slate-12">
        {{ t('OUTSIDER_TEAMS_GRAPH.APP_TITLE') }}
      </h3>
      <span
        v-if="status === 'ready'"
        class="flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
      >
        <Icon icon="i-lucide-check" class="size-3" />
        {{ t('OUTSIDER_TEAMS_GRAPH.APP_READY') }}
      </span>
      <span
        v-else
        class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-amber-3 text-n-amber-11"
      >
        {{
          status === 'consent'
            ? t('OUTSIDER_TEAMS_GRAPH.APP_NEEDS_CONSENT')
            : t('OUTSIDER_TEAMS_GRAPH.APP_MISSING')
        }}
      </span>
      <span class="ml-auto text-xs text-n-slate-10">
        {{ t('OUTSIDER_TEAMS_GRAPH.ADMINS_ONLY') }}
      </span>
    </div>
    <p class="mt-1 mb-3 text-sm text-n-slate-11">
      {{ t('OUTSIDER_TEAMS_GRAPH.APP_INTRO') }}
    </p>

    <!-- cadastro (primeira vez ou "Trocar dados") -->
    <form v-if="editing" class="flex flex-col gap-3" @submit.prevent="save">
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_TEAMS_GRAPH.CLIENT_ID') }}
          <input
            v-model="form.client_id"
            type="text"
            autocomplete="off"
            spellcheck="false"
            class="!mt-1 !mb-0 !w-full font-mono !text-sm"
            placeholder="00000000-0000-0000-0000-000000000000"
          />
        </label>
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_TEAMS_GRAPH.TENANT_ID') }}
          <input
            v-model="form.tenant_id"
            type="text"
            autocomplete="off"
            spellcheck="false"
            class="!mt-1 !mb-0 !w-full font-mono !text-sm"
            placeholder="00000000-0000-0000-0000-000000000000"
          />
        </label>
      </div>
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TEAMS_GRAPH.CLIENT_SECRET') }}
        <input
          v-model="form.client_secret"
          type="password"
          autocomplete="new-password"
          class="!mt-1 !mb-0 !w-full !text-sm"
          :placeholder="
            info.configured ? t('OUTSIDER_TEAMS_GRAPH.SECRET_KEEP') : ''
          "
        />
      </label>
      <div class="flex justify-end gap-2">
        <Button
          v-if="info.configured"
          type="button"
          sm
          slate
          faded
          :label="t('OUTSIDER_TEAMS_GRAPH.CANCEL')"
          @click="editing = false"
        />
        <Button
          type="submit"
          sm
          :label="t('OUTSIDER_TEAMS_GRAPH.SAVE_APP')"
          :is-loading="isSaving"
          :disabled="!canSave"
        />
      </div>
    </form>

    <!-- já cadastrado -->
    <template v-else>
      <div class="grid gap-3 sm:grid-cols-2">
        <div>
          <span class="block mb-1 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TEAMS_GRAPH.CLIENT_ID') }}
          </span>
          <span
            class="block px-3 py-2 font-mono text-sm border rounded-lg border-n-weak bg-n-surface-1 text-n-slate-12"
          >
            {{ short(info.app?.client_id) }}
          </span>
        </div>
        <div>
          <span class="block mb-1 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TEAMS_GRAPH.TENANT_ID') }}
          </span>
          <span
            class="block px-3 py-2 font-mono text-sm border rounded-lg border-n-weak bg-n-surface-1 text-n-slate-12"
          >
            {{ short(info.app?.tenant_id) }}
          </span>
        </div>
      </div>
      <p
        v-if="consentDate"
        class="flex items-center gap-1.5 px-2.5 py-1 mt-3 mb-0 text-xs font-semibold rounded-full w-max max-w-full bg-n-teal-3 text-n-teal-11"
      >
        <Icon icon="i-lucide-check" class="size-3.5" />
        {{ t('OUTSIDER_TEAMS_GRAPH.CONSENT_ON', { date: consentDate }) }}
      </p>
      <p
        v-else
        class="flex items-start gap-2 p-2.5 mt-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 mt-0.5 shrink-0" />
        {{ t('OUTSIDER_TEAMS_GRAPH.CONSENT_HELP') }}
      </p>
      <div class="flex flex-wrap justify-end gap-2 mt-3">
        <button
          v-if="!consentDate"
          type="button"
          class="px-3.5 py-1.5 text-sm font-semibold rounded-lg tms-accent-bg disabled:opacity-60"
          :disabled="isGoing"
          data-testid="teams-consent"
          @click="consent"
        >
          {{ t('OUTSIDER_TEAMS_GRAPH.GIVE_CONSENT') }}
        </button>
        <Button
          sm
          slate
          faded
          icon="i-lucide-key-round"
          :label="t('OUTSIDER_TEAMS_GRAPH.CHANGE_APP')"
          @click="startEdit"
        />
        <Button
          sm
          slate
          faded
          icon="i-lucide-info"
          :label="t('OUTSIDER_TEAMS_GRAPH.IT_GUIDE')"
          @click="showGuide = !showGuide"
        />
      </div>
    </template>

    <!-- passo a passo do TI -->
    <div
      v-if="showGuide"
      class="p-3 mt-4 text-sm border rounded-xl border-n-weak bg-n-surface-1 text-n-slate-11"
      data-testid="teams-it-guide"
    >
      <b class="block mb-1.5 text-n-slate-12">
        {{ t('OUTSIDER_TEAMS_GRAPH.IT_GUIDE') }}
      </b>
      <ol class="flex flex-col gap-1.5 pl-5 mb-0 list-decimal">
        <li>{{ t('OUTSIDER_TEAMS_GRAPH.GUIDE_1') }}</li>
        <li>
          {{ t('OUTSIDER_TEAMS_GRAPH.GUIDE_2') }}
          <span class="flex items-center gap-1.5 mt-1">
            <code
              class="px-2 py-1 text-xs break-all rounded-md bg-n-alpha-2 text-n-slate-12"
              >{{ info.redirect_uri }}</code
            >
            <button
              type="button"
              class="text-n-slate-11 hover:text-n-slate-12 shrink-0"
              :title="t('OUTSIDER_TEAMS_GRAPH.COPY')"
              @click="copy(info.redirect_uri)"
            >
              <Icon icon="i-lucide-copy" class="size-4" />
            </button>
          </span>
        </li>
        <li>
          {{ t('OUTSIDER_TEAMS_GRAPH.GUIDE_3') }}
          <span class="flex flex-wrap gap-1 mt-1">
            <code
              v-for="permission in info.permissions"
              :key="permission"
              class="px-1.5 py-0.5 text-[11px] rounded-md bg-n-alpha-2 text-n-slate-12"
              >{{ permission }}</code
            >
          </span>
        </li>
        <li>{{ t('OUTSIDER_TEAMS_GRAPH.GUIDE_4') }}</li>
        <li>{{ t('OUTSIDER_TEAMS_GRAPH.GUIDE_5') }}</li>
      </ol>
    </div>
  </section>
</template>
