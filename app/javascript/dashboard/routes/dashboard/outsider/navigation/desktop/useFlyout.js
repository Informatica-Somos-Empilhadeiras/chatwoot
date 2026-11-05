// OUTSIDER: o quadro que abre ao lado de um ícone com o menu recolhido (módulos, canais a mais,
// configurações). Um aberto por vez (navState.flyout); fica na altura do ícone, com a setinha
// apontando para ele, e sobe quando passaria do fim da tela.
import { computed, nextTick, ref, unref } from 'vue';
import { flyout, openFlyout, closeFlyout, keepFlyout } from './navState';

const GAP = 14;
const MARGIN = 8;

export const useFlyout = (name, triggerRef) => {
  const position = ref({ top: 0, side: 0, arrow: 22 });
  const isOpen = computed(() => flyout.name === unref(name));
  const rtl = () => document.documentElement.dir === 'rtl';

  const place = (rect, top) => ({
    top,
    side: rtl() ? window.innerWidth - rect.left + GAP : rect.right + GAP,
    arrow: rect.top + rect.height / 2 - top,
  });

  const show = async () => {
    const rect = triggerRef.value?.getBoundingClientRect();
    if (!rect) return;
    position.value = place(rect, Math.max(MARGIN, rect.top - 6));
    openFlyout(unref(name));
    await nextTick();
    const panel = document.querySelector(
      `[data-nav-flyout="${CSS.escape(unref(name))}"]`
    );
    if (!panel) return;
    const overflow =
      panel.getBoundingClientRect().bottom - (window.innerHeight - MARGIN);
    if (overflow > 0)
      position.value = place(
        rect,
        Math.max(MARGIN, position.value.top - overflow)
      );
  };

  const hide = (delay = 180) => closeFlyout(delay);

  const style = computed(() => ({
    top: `${position.value.top}px`,
    [rtl() ? 'right' : 'left']: `${position.value.side}px`,
    '--onav-arrow': `${Math.max(16, position.value.arrow)}px`,
  }));

  return { isOpen, show, hide, keep: keepFlyout, style };
};
