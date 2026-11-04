// OUTSIDER: tamanhos de tela usados pelo módulo de celular/tablet (os mesmos do Tailwind e do Chatwoot)
import { useWindowSize } from '@vueuse/core';
import { computed, reactive } from 'vue';

export const PHONE = 640; // abaixo disto: celular (sm do Tailwind)
export const SMALL_SCREEN = 768; // SMALL_SCREEN_BREAKPOINT do Chatwoot (md do Tailwind)
export const TABLET = 1024; // de 768 até aqui: tablet em pé

export const isTouch = () =>
  typeof window !== 'undefined' &&
  (window.matchMedia?.('(pointer: coarse)').matches ||
    navigator.maxTouchPoints > 0);

export const useScreen = () => {
  const { width } = useWindowSize();
  return {
    isPhone: computed(() => width.value < PHONE),
    isSmallScreen: computed(() => width.value < SMALL_SCREEN),
    isTabletPortrait: computed(
      () => width.value >= SMALL_SCREEN && width.value < TABLET
    ),
  };
};

// teclado do celular aberto (preenchido por useOutsiderResponsive a partir do visualViewport)
export const viewportState = reactive({ keyboardOpen: false });
