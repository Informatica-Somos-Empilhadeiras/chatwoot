<script setup>
// OUTSIDER (técnicos): Meu telefone, a tela inicial de quem tem o perfil Técnico (e de quem abre pelo aviso de
// ligação no celular). Só o telefone, no jeito de um app de celular: Teclado, Ramais, Recentes e Perfil na barra de
// baixo (Teams também, se o perfil deixar). Ligação chegando ou em andamento ocupa a tela toda (TechCallScreen).
// No computador fica no meio da tela, com o menu lateral do lado.
import { computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useEventListener, useIntervalFn } from '@vueuse/core';
import { phone } from '../phone';
import { allows } from '../../access/accessStore';
import TechKeypad from './TechKeypad.vue';
import TechTeam from './TechTeam.vue';
import TechRecent from './TechRecent.vue';
import TechProfile from './TechProfile.vue';
import TechCallScreen from './TechCallScreen.vue';
import {
  loadRecent,
  loadTeam,
  markRecentSeen,
  techState,
  unseenMissed,
} from './techStore';

const TABS = [
  { key: 'teclado', icon: 'i-lucide-grid-3x3', label: 'KEYPAD' },
  { key: 'ramais', icon: 'i-lucide-users', label: 'TEAM' },
  { key: 'recentes', icon: 'i-lucide-history', label: 'RECENT' },
  { key: 'perfil', icon: 'i-lucide-circle-user-round', label: 'PROFILE' },
];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const tab = computed(() =>
  TABS.some(item => item.key === route.params.tab)
    ? route.params.tab
    : 'teclado'
);
const showTeams = computed(() => allows('teams', 'use'));
const missed = computed(() => unseenMissed());
const showCall = computed(() => !!phone.call && !phone.call.monitor);

const open = key =>
  router.replace({
    name: 'outsider_my_phone',
    params: { ...route.params, tab: key === 'teclado' ? undefined : key },
  });

const openTeams = () =>
  router.push({
    name: 'outsider_teams',
    params: { accountId: route.params.accountId },
  });

const refresh = (force = false) => {
  loadTeam({ force });
  loadRecent({ force });
};

onMounted(() => refresh(true));
useIntervalFn(() => {
  if (!document.hidden) refresh(true);
}, 60000);
useEventListener(document, 'visibilitychange', () => {
  if (!document.hidden) refresh(true);
});
// ligação acabou: Recentes e quem está em ligação mudam
watch(
  () => phone.call?.state,
  (state, before) => {
    if (state === 'ended' || (!state && before)) refresh(true);
  }
);
watch(
  [tab, () => techState.recent.length],
  () => {
    if (tab.value === 'recentes') markRecentSeen();
  },
  { immediate: true }
);
</script>

<template>
  <section
    class="outsider-tech flex justify-center w-full h-full overflow-hidden bg-n-background"
    data-outsider-tech-phone
    data-testid="outsider-tech-phone"
  >
    <div
      class="outsider-tech__app relative flex flex-col w-full h-full max-w-[28rem] bg-n-solid-1 md:my-4 md:h-[calc(100%-2rem)] md:rounded-3xl md:border md:border-n-weak md:shadow-lg overflow-hidden"
    >
      <div
        v-if="phone.status === 'off'"
        class="flex flex-col items-center justify-center flex-1 gap-3 px-8 text-center"
      >
        <span class="i-lucide-phone-off size-12 text-n-slate-9" />
        <p class="text-lg font-semibold text-n-slate-12">
          {{ t('OUTSIDER_VOICE.TECH.OFF_TITLE') }}
        </p>
        <p class="text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.TECH.OFF_TEXT') }}
        </p>
      </div>
      <div v-else class="flex-1 min-h-0 overflow-y-auto">
        <TechKeypad v-if="tab === 'teclado'" />
        <TechTeam v-else-if="tab === 'ramais'" />
        <TechRecent v-else-if="tab === 'recentes'" />
        <TechProfile v-else />
      </div>

      <nav
        class="outsider-tech__tabs flex shrink-0 border-t border-n-weak bg-n-solid-1"
        :aria-label="t('OUTSIDER_VOICE.TECH.TITLE')"
      >
        <button
          v-for="item in TABS"
          :key="item.key"
          type="button"
          class="outsider-tech__tab"
          :class="{ 'is-on': tab === item.key }"
          :data-testid="`outsider-tech-tab-${item.key}`"
          @click="open(item.key)"
        >
          <span class="outsider-tech__tab-icon">
            <span :class="item.icon" class="size-5" />
            <span
              v-if="item.key === 'recentes' && missed"
              class="outsider-tech__badge"
            >
              {{ missed }}
            </span>
          </span>
          {{ t(`OUTSIDER_VOICE.TECH.TABS.${item.label}`) }}
        </button>
        <button
          v-if="showTeams"
          type="button"
          class="outsider-tech__tab"
          data-testid="outsider-tech-tab-teams"
          @click="openTeams"
        >
          <span class="outsider-tech__tab-icon">
            <span class="i-lucide-messages-square size-5" />
          </span>
          {{ t('OUTSIDER_VOICE.TECH.TABS.TEAMS') }}
        </button>
      </nav>

      <TechCallScreen v-if="showCall" />
    </div>
  </section>
</template>

<style scoped>
.outsider-tech {
  height: var(--outsider-app-height, 100%);
}

.outsider-tech__tabs {
  padding-bottom: env(safe-area-inset-bottom, 0);
}

.outsider-tech__tab {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.25rem;
  padding: 0.5rem 0 0.625rem;
  font-size: 0.72rem;
  font-weight: 500;
  color: rgb(var(--slate-11));
}

.outsider-tech__tab.is-on {
  color: var(--outsider-brand-text, #00663b);
  font-weight: 700;
}

.outsider-tech__tab-icon {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0.2rem 1rem;
  border-radius: 1rem;
}

.outsider-tech__tab.is-on .outsider-tech__tab-icon {
  background: color-mix(
    in srgb,
    var(--outsider-brand, #00663b) 14%,
    transparent
  );
}

.outsider-tech__badge {
  position: absolute;
  top: -0.35rem;
  right: 0.35rem;
  min-width: 1.05rem;
  padding: 0 0.3rem;
  border-radius: 999px;
  background: #e53935;
  color: #fff;
  font-size: 0.65rem;
  font-weight: 700;
  line-height: 1.05rem;
  text-align: center;
}
</style>

<style>
/* o botão redondo do menu do Chatwoot não fica por cima da barra de baixo do Meu telefone */
body:has([data-outsider-tech-phone]) #mobile-sidebar-launcher {
  display: none !important;
}
</style>
