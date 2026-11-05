// OUTSIDER: o que o menu lateral lembra entre uma visita e outra, neste navegador:
// quais grupos (Canais, Pastas, Times, Etiquetas...) estão abertos e quais listas estão "ver todos".
import { reactive, watch } from 'vue';

const KEY = 'outsider-nav-v1';
// Canais começa aberto: é por onde mais se troca de conversa
const DEFAULT = { groups: { Channels: true }, showAll: {} };

const load = () => {
  try {
    const saved = JSON.parse(window.localStorage.getItem(KEY) || 'null');
    return saved && typeof saved === 'object'
      ? { ...DEFAULT, ...saved }
      : DEFAULT;
  } catch {
    return DEFAULT;
  }
};

export const navState = reactive(load());

watch(
  navState,
  value => {
    try {
      window.localStorage.setItem(KEY, JSON.stringify(value));
    } catch {
      // navegador sem armazenamento: só não lembra
    }
  },
  { deep: true }
);

export const isGroupOpen = name => navState.groups[name] ?? false;
export const toggleGroup = name => {
  navState.groups[name] = !isGroupOpen(name);
};
export const isShowingAll = name => !!navState.showAll[name];
export const toggleShowAll = name => {
  navState.showAll[name] = !isShowingAll(name);
};

// quadro que abre ao lado de um ícone com o menu recolhido (um por vez)
export const flyout = reactive({ name: null });
let closeTimer = null;
export const openFlyout = name => {
  clearTimeout(closeTimer);
  flyout.name = name;
};
export const closeFlyout = (delay = 0) => {
  clearTimeout(closeTimer);
  if (!delay) {
    flyout.name = null;
    return;
  }
  closeTimer = setTimeout(() => {
    flyout.name = null;
  }, delay);
};
export const keepFlyout = () => clearTimeout(closeTimer);
