<script setup>
// OUTSIDER: o botão redondo do telefone, fixo no canto inferior esquerdo do aplicativo (logo ao lado
// do menu lateral), no computador e no tablet. Agente: abre o teclado do telefone. Administrador:
// abre um menu com "Ligar" e os painéis da Telefonia. Só aparece com ramal ligado. No celular o
// botão fica no meio da barra de baixo (responsive/MobileTabbar.vue), então aqui ele some.
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { onClickOutside, useEventListener, useWindowSize } from '@vueuse/core';
import { SMALL_SCREEN } from '../responsive/screen';
import { VOICE_ROUTE } from './sections';
import { phone, panel } from './phone';
import {
  PHONE_DOT,
  phoneState,
  revealPhone,
  togglePhone,
  usePhonePanels,
} from './phoneMenu';

// a janela própria do telefone já é o telefone
const HIDDEN_ROUTES = ['outsider_phone_window', 'outsider_my_phone'];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { width } = useWindowSize();
const { panels } = usePhonePanels();

const state = computed(() => phoneState());
const inCall = computed(() => state.value === 'in_call');
const visible = computed(
  () =>
    phone.status !== 'off' &&
    width.value >= SMALL_SCREEN &&
    !HIDDEN_ROUTES.includes(route.name)
);
const statusText = computed(() => {
  const status = t(`OUTSIDER_NAV.PHONE.STATUS.${state.value}`);
  return phone.extension
    ? `${status} · ${t('OUTSIDER_NAV.PHONE.EXTENSION', { extension: phone.extension })}`
    : status;
});
const title = computed(
  () => `${t('OUTSIDER_NAV.PHONE.TITLE')} · ${statusText.value}`
);
const dotClass = computed(() => PHONE_DOT[state.value] || PHONE_DOT.offline);
// logo ao lado do menu lateral (DesktopNav grava a largura dele em --outsider-nav-width)
const fabStyle = computed(() => ({
  [document.documentElement.dir === 'rtl' ? 'right' : 'left']:
    'calc(var(--outsider-nav-width, 0px) + 1rem)',
}));

// menu do administrador, aberto logo acima do botão
const menuOpen = ref(false);
const button = ref(null);
const menu = ref(null);
const menuStyle = ref({});

const placeMenu = () => {
  const rect = button.value?.getBoundingClientRect();
  if (!rect) return;
  menuStyle.value = {
    left: `${rect.left}px`,
    bottom: `${window.innerHeight - rect.top + 10}px`,
  };
};
const closeMenu = () => {
  menuOpen.value = false;
};
const onClick = () => {
  if (!panels.value.length) {
    togglePhone();
    return;
  }
  if (menuOpen.value) {
    closeMenu();
    return;
  }
  placeMenu();
  menuOpen.value = true;
};
const call = () => {
  closeMenu();
  revealPhone(true);
};
const goPanel = item => {
  closeMenu();
  router.push(item.to).catch(() => {});
};
const isCurrent = item =>
  route.name === VOICE_ROUTE && route.params.tab === item.key;

onClickOutside(menu, closeMenu, { ignore: [button] });
useEventListener(window, 'keydown', event => {
  if (event.key === 'Escape') closeMenu();
});
useEventListener(window, 'resize', () => menuOpen.value && placeMenu());
watch(() => route.fullPath, closeMenu);
watch(visible, value => {
  if (!value) closeMenu();
});
</script>

<template>
  <Teleport to="body">
    <button
      v-if="visible"
      ref="button"
      type="button"
      class="fixed z-40 grid place-items-center text-white transition rounded-full shadow-lg outline-none size-[3.25rem] bg-n-brand shadow-black/25 hover:brightness-110 active:scale-95 focus-visible:ring-2 focus-visible:ring-n-brand focus-visible:ring-offset-2 bottom-4"
      :class="{ 'ring-4 ring-n-brand/30': panel.open || menuOpen }"
      :style="fabStyle"
      :title="title"
      :aria-label="title"
      :aria-expanded="panels.length ? menuOpen : undefined"
      data-testid="outsider-phone-fab"
      @click="onClick"
    >
      <span
        v-if="inCall"
        class="absolute inset-0 rounded-full ring-4 ring-n-teal-9/50 animate-ping"
      />
      <span
        :class="inCall ? 'i-lucide-phone-call' : 'i-lucide-phone'"
        class="size-6"
      />
      <span
        class="absolute bottom-0.5 ltr:right-0.5 rtl:left-0.5 size-3 rounded-full ring-2 ring-n-background"
        :class="dotClass"
      />
    </button>
    <div
      v-if="visible && menuOpen"
      ref="menu"
      class="fixed z-40 flex flex-col w-64 gap-0.5 p-2 border shadow-2xl rounded-2xl border-n-weak bg-n-solid-1"
      :style="menuStyle"
      role="menu"
      data-testid="outsider-phone-menu"
    >
      <div class="flex flex-col px-2 pt-1 pb-2">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t('OUTSIDER_NAV.PHONE.TITLE') }}
        </span>
        <span class="text-xs text-n-slate-11">{{ statusText }}</span>
      </div>
      <button
        type="button"
        role="menuitem"
        class="flex items-center gap-3 px-3 text-sm font-semibold text-white rounded-xl h-10 bg-n-brand hover:brightness-110"
        data-testid="outsider-phone-menu-call"
        @click="call"
      >
        <span
          :class="inCall ? 'i-lucide-phone-call' : 'i-lucide-phone-outgoing'"
          class="size-4 shrink-0"
        />
        {{
          inCall ? t('OUTSIDER_NAV.PHONE.OPEN') : t('OUTSIDER_NAV.PHONE.CALL')
        }}
      </button>
      <div
        class="px-3 pt-3 pb-1 text-[11px] font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_NAV.PHONE.PANELS') }}
      </div>
      <button
        v-for="item in panels"
        :key="item.key"
        type="button"
        role="menuitem"
        class="flex items-center gap-3 px-3 text-sm text-left rounded-xl h-9 text-n-slate-12"
        :class="
          isCurrent(item)
            ? 'bg-n-brand/10 text-n-brand font-semibold dark:text-n-slate-12'
            : 'hover:bg-n-alpha-2'
        "
        @click="goPanel(item)"
      >
        <span :class="item.icon" class="size-4 shrink-0 text-n-slate-11" />
        <span class="truncate">{{ t(item.label) }}</span>
      </button>
    </div>
  </Teleport>
</template>
