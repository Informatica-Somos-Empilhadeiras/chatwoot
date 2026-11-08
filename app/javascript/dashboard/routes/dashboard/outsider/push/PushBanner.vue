<script setup>
// OUTSIDER: aviso para ativar as notificações neste aparelho (o navegador só deixa pedir a licença depois de um clique).
// Fica até a pessoa ativar; se fechar, volta no dia seguinte (ou na hora, se um administrador mandar um lembrete).
// Também abre a conversa quando a pessoa clica num aviso e o Chatwoot já está aberto (mensagem do service worker).
// Fora das Configurações é um cartão no canto de baixo (não tampa cabeçalhos nem a caixa de resposta); na página
// Minhas notificações aparece no topo da página (inline) e o cartão flutuante some.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { activatePush, loadPush, pushState, syncDevice } from './pushDevice';

const props = defineProps({
  inline: { type: Boolean, default: false },
});

const DISMISS_KEY = 'outsider_push_banner_closed';
const SETTINGS_ROUTE = 'outsider_push_settings';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const mainLeft = ref(16);
const accountId = useMapGetter('getCurrentAccountId');
const closedAt = ref(null);
const isActivating = ref(false);

const readClosed = () => {
  try {
    closedAt.value = localStorage.getItem(DISMISS_KEY);
  } catch {
    closedAt.value = null;
  }
};

const closedToday = computed(() => {
  if (!closedAt.value) return false;
  const closed = new Date(closedAt.value);
  const reminded = pushState.info?.reminded_at
    ? new Date(pushState.info.reminded_at)
    : null;
  if (reminded && reminded > closed) return false;
  return closed.toDateString() === new Date().toDateString();
});

const mode = computed(() => {
  const info = pushState.info;
  if (!pushState.loaded || !info?.enabled || !info.vapid) return null;
  if (!pushState.supported || closedToday.value) return null;
  if (!props.inline && route.name === SETTINGS_ROUTE) return null;
  if (pushState.permission === 'default') return 'ask';
  // na página de notificações o cartão "Meus aparelhos" já explica o bloqueio
  if (pushState.permission === 'denied') return props.inline ? null : 'blocked';
  return null;
});

const reminded = computed(() => !!pushState.info?.reminded_at);

const close = () => {
  const now = new Date().toISOString();
  closedAt.value = now;
  try {
    localStorage.setItem(DISMISS_KEY, now);
  } catch {
    // sem localStorage o aviso só volta ao recarregar
  }
};

const activate = async () => {
  isActivating.value = true;
  try {
    const ok = await activatePush();
    useAlert(
      ok
        ? t('OUTSIDER_PUSH.BANNER.DONE')
        : t('OUTSIDER_PUSH.BANNER.NOT_ALLOWED')
    );
  } catch (error) {
    useAlert(t('OUTSIDER_PUSH.BANNER.FAILED'));
  } finally {
    isActivating.value = false;
  }
};

const start = async id => {
  if (!id) return;
  readClosed();
  try {
    await loadPush();
    await syncDevice();
  } catch {
    // sem push o resto do Chatwoot segue normal
  }
};

// clicou no aviso com o Chatwoot aberto: troca a tela sem recarregar
const onWorkerMessage = event => {
  const data = event.data || {};
  if (data.type !== 'outsider:push-open' || !data.path) return;
  router.push(data.path).catch(() => {});
};

// o cartão flutuante começa onde começa a área da página (depois do menu lateral)
const placeCard = () => {
  const main = document.querySelector('main');
  mainLeft.value = main
    ? Math.round(main.getBoundingClientRect().left) + 12
    : 12;
};

const cardStyle = computed(() =>
  props.inline ? {} : { '--outsider-push-left': `${mainLeft.value}px` }
);

// a página de configurações só mostra o aviso; quem carrega e escuta o service worker é o global
if (!props.inline) watch(accountId, start, { immediate: true });

watch(mode, value => {
  if (value && !props.inline) setTimeout(placeCard);
});

onMounted(() => {
  if (props.inline) return;
  window.addEventListener('resize', placeCard);
  if ('serviceWorker' in navigator)
    navigator.serviceWorker.addEventListener('message', onWorkerMessage);
});

onBeforeUnmount(() => {
  if (props.inline) return;
  window.removeEventListener('resize', placeCard);
  if ('serviceWorker' in navigator)
    navigator.serviceWorker.removeEventListener('message', onWorkerMessage);
});
</script>

<template>
  <div
    v-if="mode"
    class="flex gap-3 px-4 py-3 border rounded-2xl bg-n-amber-2 border-n-amber-6"
    :class="
      inline
        ? 'relative items-center mb-4'
        : 'fixed z-40 shadow-lg outsider-push-card w-[min(330px,calc(100vw-1.5rem))]'
    "
    :style="cardStyle"
    role="status"
    data-outsider-push-banner
  >
    <span
      class="grid rounded-full place-items-center shrink-0 bg-n-amber-9 text-white"
      :class="inline ? 'size-10' : 'size-9'"
    >
      <Icon
        :icon="mode === 'ask' ? 'i-lucide-bell-ring' : 'i-lucide-bell-off'"
        class="size-5"
      />
    </span>
    <span class="flex-1 min-w-0 text-sm" :class="{ 'pr-5': !inline }">
      <b class="block text-n-slate-12">
        {{
          mode === 'ask'
            ? t('OUTSIDER_PUSH.BANNER.TITLE')
            : t('OUTSIDER_PUSH.BANNER.BLOCKED_TITLE')
        }}
      </b>
      <span class="block text-n-slate-11">
        <template v-if="mode === 'ask'">
          {{
            reminded
              ? t('OUTSIDER_PUSH.BANNER.REMINDED')
              : t('OUTSIDER_PUSH.BANNER.TEXT')
          }}
        </template>
        <template v-else>{{ t('OUTSIDER_PUSH.BANNER.BLOCKED_TEXT') }}</template>
      </span>
      <!-- cartão flutuante: botões embaixo do texto -->
      <span v-if="!inline" class="flex items-center gap-2 mt-2.5">
        <button
          v-if="mode === 'ask'"
          type="button"
          class="px-3.5 py-1.5 text-sm font-semibold text-white rounded-xl bg-n-amber-9 hover:bg-n-amber-10 disabled:opacity-60"
          :disabled="isActivating"
          data-outsider-push-activate
          @click="activate"
        >
          {{ t('OUTSIDER_PUSH.BANNER.ACTIVATE') }}
        </button>
        <button
          type="button"
          class="px-2.5 py-1.5 text-sm font-medium rounded-xl text-n-slate-11 hover:bg-n-alpha-2"
          @click="close"
        >
          {{ t('OUTSIDER_PUSH.BANNER.CLOSE') }}
        </button>
      </span>
    </span>
    <button
      v-if="inline && mode === 'ask'"
      type="button"
      class="px-3.5 py-2 text-sm font-semibold text-white rounded-xl shrink-0 bg-n-amber-9 hover:bg-n-amber-10 disabled:opacity-60"
      :disabled="isActivating"
      data-outsider-push-activate
      @click="activate"
    >
      {{ t('OUTSIDER_PUSH.BANNER.ACTIVATE') }}
    </button>
    <button
      type="button"
      class="grid rounded-lg size-8 place-items-center shrink-0 text-n-slate-11 hover:bg-n-alpha-2"
      :class="{ 'absolute top-2 right-2': !inline }"
      :title="t('OUTSIDER_PUSH.BANNER.CLOSE')"
      @click="close"
    >
      <Icon icon="i-lucide-x" class="size-4" />
    </button>
  </div>
</template>

<style scoped>
.outsider-push-card {
  left: var(--outsider-push-left, 1rem);
  bottom: 1rem;
}

/* celular: fica acima da barra de abas de baixo */
@media (max-width: 767px) {
  .outsider-push-card {
    left: 0.75rem;
    right: 0.75rem;
    width: auto;
    bottom: calc(4.75rem + env(safe-area-inset-bottom));
  }
}
</style>
