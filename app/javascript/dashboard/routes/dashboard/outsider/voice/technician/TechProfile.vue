<script setup>
// OUTSIDER (técnicos): aba Perfil do Meu telefone: a situação (Disponível, Ocupado, Offline), a linha do telefone
// (reconectar, trazer para este aparelho, testar o som), o aviso de ligação neste celular (ativar e testar) e
// instalar o Chatwoot como app. Tudo o que o técnico precisa para receber ligações com o celular no bolso.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Auth from 'dashboard/api/auth';
import { phone, dial, restartPhone, useThisTab } from '../phone';
import TechHeader from './TechHeader.vue';
import { installApp, installState } from './installPrompt';
import { useTechPush } from './useTechPush';

const STATUSES = [
  { key: 'online', dot: '#22c55e' },
  { key: 'busy', dot: '#f59e0b' },
  { key: 'offline', dot: '#94a3b8' },
];

const { t } = useI18n();
const store = useStore();
const availability = useMapGetter('getCurrentUserAvailability');
const accountId = useMapGetter('getCurrentAccountId');

const { pushStatus, working, enablePush, testPush, apple } = useTechPush();
const android = /Android/.test(navigator.userAgent);

const lineState = computed(() => {
  if (phone.sleeping) return 'SLEEPING';
  return (
    {
      ready: 'READY',
      connecting: 'CONNECTING',
      offline: 'OFFLINE',
      failed: 'FAILED',
      other_tab: 'OTHER_TAB',
    }[phone.status] || 'OFFLINE'
  );
});

const setStatus = key => {
  if (key === availability.value) return;
  store
    .dispatch('updateAvailability', {
      availability: key,
      account_id: accountId.value,
    })
    .catch(() =>
      useAlert(t('PROFILE_SETTINGS.FORM.AVAILABILITY.SET_AVAILABILITY_ERROR'))
    );
};

const testAudio = () => {
  const error = dial(phone.echoExtension);
  if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
};

const install = async () => {
  await installApp();
};

const logout = () => Auth.logout();
</script>

<template>
  <div class="pb-6">
    <TechHeader />

    <section class="outsider-tech-card">
      <h2>{{ t('OUTSIDER_VOICE.TECH.PROFILE.STATUS') }}</h2>
      <div class="grid grid-cols-3 gap-2">
        <button
          v-for="item in STATUSES"
          :key="item.key"
          type="button"
          class="outsider-tech-status"
          :class="{ 'is-on': availability === item.key }"
          :data-testid="`outsider-tech-availability-${item.key}`"
          @click="setStatus(item.key)"
        >
          <span
            class="size-2.5 rounded-full"
            :style="{ background: item.dot }"
          />
          {{ t(`OUTSIDER_VOICE.TECH.AVAILABILITY.${item.key.toUpperCase()}`) }}
        </button>
      </div>
      <p class="mt-2 text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.TECH.PROFILE.STATUS_HINT') }}
      </p>
    </section>

    <section class="outsider-tech-card">
      <h2>{{ t('OUTSIDER_VOICE.TECH.PROFILE.LINE') }}</h2>
      <p class="text-sm text-n-slate-12" data-testid="outsider-tech-line-state">
        {{
          t(`OUTSIDER_VOICE.TECH.LINE_STATE.${lineState}`, {
            extension: phone.extension,
          })
        }}
      </p>
      <div class="flex flex-wrap gap-2 mt-3">
        <button
          v-if="phone.status === 'other_tab'"
          type="button"
          class="outsider-tech-button is-primary"
          @click="useThisTab"
        >
          {{ t('OUTSIDER_VOICE.TECH.PROFILE.USE_HERE') }}
        </button>
        <button
          v-else-if="
            ['offline', 'failed'].includes(phone.status) && !phone.sleeping
          "
          type="button"
          class="outsider-tech-button is-primary"
          @click="restartPhone"
        >
          {{ t('OUTSIDER_VOICE.TECH.PROFILE.RECONNECT') }}
        </button>
        <button
          v-if="phone.echoExtension"
          type="button"
          class="outsider-tech-button"
          :disabled="phone.status !== 'ready'"
          data-testid="outsider-tech-test-audio"
          @click="testAudio"
        >
          <span class="i-lucide-volume-2 size-4" />
          {{ t('OUTSIDER_VOICE.TECH.PROFILE.TEST_AUDIO') }}
        </button>
      </div>
    </section>

    <section class="outsider-tech-card" data-testid="outsider-tech-push">
      <h2>{{ t('OUTSIDER_VOICE.TECH.PROFILE.PUSH') }}</h2>
      <p class="text-sm text-n-slate-12">
        {{ t(`OUTSIDER_VOICE.TECH.PUSH.${pushStatus}`) }}
      </p>
      <div class="flex flex-wrap gap-2 mt-3">
        <button
          v-if="pushStatus === 'OFF'"
          type="button"
          class="outsider-tech-button is-primary"
          :disabled="working"
          data-testid="outsider-tech-enable-push"
          @click="enablePush"
        >
          <span class="i-lucide-bell-ring size-4" />
          {{ t('OUTSIDER_VOICE.TECH.PUSH.ENABLE') }}
        </button>
        <button
          v-if="pushStatus === 'ACTIVE'"
          type="button"
          class="outsider-tech-button"
          @click="testPush"
        >
          {{ t('OUTSIDER_VOICE.TECH.PUSH.TEST') }}
        </button>
      </div>
      <p v-if="pushStatus === 'BLOCKED'" class="mt-2 text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.TECH.PUSH.BLOCKED_HINT') }}
      </p>
    </section>

    <section class="outsider-tech-card">
      <h2>{{ t('OUTSIDER_VOICE.TECH.PROFILE.APP') }}</h2>
      <p v-if="installState.installed" class="text-sm text-n-slate-12">
        {{ t('OUTSIDER_VOICE.TECH.INSTALL.DONE') }}
      </p>
      <template v-else>
        <p class="text-sm text-n-slate-12">
          {{ t('OUTSIDER_VOICE.TECH.INSTALL.WHY') }}
        </p>
        <button
          v-if="installState.prompt"
          type="button"
          class="mt-3 outsider-tech-button is-primary"
          @click="install"
        >
          <span class="i-lucide-download size-4" />
          {{ t('OUTSIDER_VOICE.TECH.INSTALL.BUTTON') }}
        </button>
        <p v-else-if="apple" class="mt-2 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.TECH.INSTALL.IPHONE') }}
        </p>
        <p v-else-if="android" class="mt-2 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.TECH.INSTALL.ANDROID') }}
        </p>
        <p v-else class="mt-2 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.TECH.INSTALL.DESKTOP') }}
        </p>
      </template>
    </section>

    <div class="px-4 mt-4">
      <button
        type="button"
        class="w-full outsider-tech-button is-danger"
        data-testid="outsider-tech-logout"
        @click="logout"
      >
        <span class="i-lucide-log-out size-4" />
        {{ t('OUTSIDER_VOICE.TECH.PROFILE.LOGOUT') }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.outsider-tech-card {
  margin: 0.75rem 1rem 0;
  padding: 0.875rem 1rem;
  border-radius: 1rem;
  border: 1px solid rgb(var(--slate-4));
}

.outsider-tech-card h2 {
  margin-bottom: 0.5rem;
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: rgb(var(--slate-11));
}

.outsider-tech-status {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  padding: 0.6rem 0.25rem;
  border-radius: 0.75rem;
  font-size: 0.8rem;
  font-weight: 600;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.outsider-tech-status.is-on {
  outline: 2px solid var(--outsider-brand, #00663b);
  background: color-mix(
    in srgb,
    var(--outsider-brand, #00663b) 10%,
    transparent
  );
}

.outsider-tech-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  padding: 0.55rem 0.9rem;
  border-radius: 0.75rem;
  font-size: 0.85rem;
  font-weight: 600;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.outsider-tech-button:disabled {
  opacity: 0.5;
}

.outsider-tech-button.is-primary {
  background: var(--outsider-brand, #00663b);
  color: #fff;
}

.outsider-tech-button.is-danger {
  background: #fee2e2;
  color: #b91c1c;
}
</style>
