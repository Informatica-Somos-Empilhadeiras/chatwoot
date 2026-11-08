<script setup>
// OUTSIDER: Configurações > Microsoft Teams.
//   Todos: "Meu Teams": entrar com a conta Microsoft, escolher chats e canais, entrar de novo, desconectar.
//   Administradores: o aplicativo da empresa (cadastro único do TI), quem está conectado (sem o
//   conteúdo das conversas) e, recolhido, o robô do Teams da Entrega 26.
// A volta do login da Microsoft chega aqui (?teams_oauth[...]) e é terminada com a sessão da pessoa.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeamsLogo from './TeamsLogo.vue';
import MyTeamsCard from './MyTeamsCard.vue';
import TeamsCompanyApp from './TeamsCompanyApp.vue';
import TeamsPeople from './TeamsPeople.vue';
import TeamsBotSection from './TeamsBotSection.vue';
import { loadTeamsSummary } from './teamsStore';
import { errorText } from './helpers';
import './teams.css';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const isLoading = ref(true);
const isFinishing = ref(false);
const info = ref(null);

const isAdmin = computed(() => !!info.value?.admin);

const load = async () => {
  try {
    const { data } = await TeamsGraphAPI.settings();
    info.value = data;
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isLoading.value = false;
  }
};

const oauthParams = () => {
  const keys = ['code', 'state', 'error', 'error_description', 'admin_consent'];
  const found = {};
  keys.forEach(key => {
    const value = route.query[`teams_oauth[${key}]`];
    if (value) found[key] = value;
  });
  return found.state || found.error ? found : null;
};

// volta da Microsoft: termina o login (ou o consentimento) e limpa o endereço
const finishOAuth = async params => {
  isFinishing.value = true;
  router.replace({ query: {} });
  try {
    await TeamsGraphAPI.finish(params);
    useAlert(
      params.admin_consent
        ? t('OUTSIDER_TEAMS_GRAPH.CONSENT_DONE')
        : t('OUTSIDER_TEAMS_GRAPH.CONNECTED_DONE')
    );
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isFinishing.value = false;
  }
};

const refresh = async () => {
  await load();
  loadTeamsSummary(route.params.accountId);
};

onMounted(async () => {
  const params = oauthParams();
  if (params) await finishOAuth(params);
  await refresh();
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading || isFinishing" class="tms">
    <template #header>
      <BaseSettingsHeader
        :title="t('OUTSIDER_TEAMS_GRAPH.TITLE')"
        :description="t('OUTSIDER_TEAMS_GRAPH.DESCRIPTION')"
      >
        <template #title>
          <h1 class="flex items-center gap-2.5 text-heading-1 text-n-slate-12">
            <TeamsLogo :size="26" />
            {{ t('OUTSIDER_TEAMS_GRAPH.TITLE') }}
          </h1>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div v-if="info" class="tms flex flex-col gap-4 pb-8">
        <div
          v-if="isAdmin && !info.public_https"
          class="flex items-start gap-2.5 p-3 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
        >
          <Icon icon="i-lucide-triangle-alert" class="size-4 mt-0.5 shrink-0" />
          <span>{{ t('OUTSIDER_TEAMS_GRAPH.NOT_PUBLIC') }}</span>
        </div>

        <div
          class="grid gap-4"
          :class="isAdmin && !info.me ? 'lg:grid-cols-[1fr_1.15fr]' : ''"
        >
          <MyTeamsCard :info="info" @changed="refresh" />
          <TeamsCompanyApp
            v-if="isAdmin && !info.me"
            :info="info"
            @changed="refresh"
          />
        </div>
        <TeamsCompanyApp
          v-if="isAdmin && info.me"
          :info="info"
          @changed="refresh"
        />
        <TeamsPeople v-if="isAdmin" :links="info.links" @changed="refresh" />

        <div
          class="flex items-start gap-2.5 p-3 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
        >
          <Icon icon="i-lucide-eye-off" class="size-4 mt-0.5 shrink-0" />
          <span>
            <b class="text-n-slate-12">{{ t('OUTSIDER_TEAMS_GRAPH.PRIVACY_TITLE') }}</b>
            {{ t('OUTSIDER_TEAMS_GRAPH.PRIVACY') }}
          </span>
        </div>

        <TeamsBotSection v-if="isAdmin" />
      </div>
    </template>
  </SettingsLayout>
</template>
