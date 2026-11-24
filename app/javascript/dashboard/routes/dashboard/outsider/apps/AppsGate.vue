<script setup>
// OUTSIDER: o que a tela de um aplicativo mostra antes de funcionar: carregando, "Conecte sua conta" (nunca entrou),
// "Entre de novo" (a Microsoft não aceita mais o acesso, ou faltam as permissões novas, ex.: Outlook pede a versão 4).
// O botão leva para Configurações > Meu Teams, onde a pessoa entra com a própria conta.
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AppLogo from './AppLogo.vue';
import { providerOf } from './providers';

const props = defineProps({
  provider: { type: String, required: true },
  // 'loading' | 'disconnected' | 'reconnect' | 'scope'
  state: { type: String, required: true },
  logo: { type: String, required: true },
  appName: { type: String, required: true },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const info = computed(() => providerOf(props.provider));

const title = computed(
  () =>
    ({
      disconnected: t('OUTSIDER_APPS.GATE.CONNECT_TITLE', {
        app: props.appName,
      }),
      reconnect: t('OUTSIDER_APPS.GATE.RECONNECT_TITLE'),
      scope: t('OUTSIDER_APPS.GATE.SCOPE_TITLE', { app: props.appName }),
    })[props.state] || ''
);
const text = computed(
  () =>
    ({
      disconnected: t('OUTSIDER_APPS.GATE.CONNECT_TEXT', {
        company: t(info.value.company),
      }),
      reconnect: t('OUTSIDER_APPS.GATE.RECONNECT_TEXT'),
      scope: t('OUTSIDER_APPS.GATE.SCOPE_TEXT', { app: props.appName }),
    })[props.state] || ''
);

const go = () =>
  router.push({
    name: info.value.settingsRoute,
    params: { accountId: route.params.accountId },
  });
</script>

<template>
  <div
    class="flex flex-col items-center justify-center flex-1 gap-3 p-8 text-center"
    :data-apps-gate="state"
  >
    <Spinner v-if="state === 'loading'" :size="22" />
    <template v-else>
      <span
        class="grid size-16 place-items-center rounded-2xl bg-n-alpha-2 shrink-0"
      >
        <AppLogo :name="logo" :size="36" />
      </span>
      <h2 class="mb-0 text-lg font-semibold text-n-slate-12">{{ title }}</h2>
      <p class="max-w-md mb-0 text-sm text-n-slate-11">{{ text }}</p>
      <button type="button" class="oa-btn" @click="go">
        <Icon
          :icon="
            state === 'disconnected' ? 'i-lucide-log-in' : 'i-lucide-refresh-cw'
          "
          class="size-4"
        />
        {{
          state === 'disconnected'
            ? t('OUTSIDER_APPS.GATE.CONNECT_BUTTON')
            : t('OUTSIDER_APPS.GATE.RECONNECT_BUTTON')
        }}
      </button>
    </template>
  </div>
</template>
