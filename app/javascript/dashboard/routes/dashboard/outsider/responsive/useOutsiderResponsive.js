// OUTSIDER: Chatwoot no celular e no tablet (navegador e app instalado pelo navegador).
// Tudo o que é comportamento fica aqui e o visual fica em responsive.css; os dois entram pelo
// OutsiderGlobal.vue, então nenhum arquivo original do Chatwoot precisa saber deste módulo.
//
// 1. Altura real da tela: o Chatwoot usa 100vh, que no celular é maior que a parte visível
//    (barra do navegador) e não diminui quando o teclado abre. Aqui a altura visível vai para a
//    variável --outsider-app-height, que o responsive.css usa no #app, e a caixa de texto fica
//    sempre logo acima do teclado (Android e iPhone).
// 2. Painel do contato: no celular ele cobre a tela inteira, e a preferência "aberto" vem do
//    computador. Ao entrar numa conversa pelo celular ele começa fechado (abre tocando no nome).
// 3. Arrastar no toque: as seções do painel do contato, atributos e macros não se mexem mais
//    quando o dedo só quer rolar a tela.
import { watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { isTouch, SMALL_SCREEN, viewportState } from './screen';

// --- 1. altura visível -------------------------------------------------------------------
const setViewportMeta = () => {
  // Android/Chrome: o teclado encolhe a página em vez de cobrir a parte de baixo
  const meta = document.querySelector('meta[name="viewport"]');
  if (meta && !meta.content.includes('interactive-widget')) {
    meta.content = `${meta.content}, interactive-widget=resizes-content`;
  }
};

const startViewportHeight = () => {
  const root = document.documentElement;
  const viewport = window.visualViewport;
  let frame = 0;

  const apply = () => {
    frame = 0;
    const height = Math.round(viewport ? viewport.height : window.innerHeight);
    root.style.setProperty('--outsider-app-height', `${height}px`);
    const keyboardOpen = viewport && window.innerHeight - viewport.height > 120;
    root.classList.toggle('outsider-keyboard-open', !!keyboardOpen);
    viewportState.keyboardOpen = !!keyboardOpen;
    // iPhone: com o teclado aberto o Safari empurra a página para cima; a página fica parada
    // e só encolhe, assim o cabeçalho continua no topo e a caixa de texto em cima do teclado
    if (viewport && viewport.offsetTop > 0 && window.scrollY !== 0) {
      window.scrollTo(0, 0);
    }
  };
  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(apply);
  };

  apply();
  viewport?.addEventListener('resize', schedule);
  viewport?.addEventListener('scroll', schedule);
  window.addEventListener('resize', schedule);
  window.addEventListener('orientationchange', schedule);
  return () => {
    viewport?.removeEventListener('resize', schedule);
    viewport?.removeEventListener('scroll', schedule);
    window.removeEventListener('resize', schedule);
    window.removeEventListener('orientationchange', schedule);
    if (frame) cancelAnimationFrame(frame);
  };
};

// --- 3. no toque, as alças de arrastar não arrastam ---------------------------------------
// Seções do painel do contato, atributos e macros se reordenam pela alça ".drag-handle" (o
// cabeçalho inteiro da seção). No toque, o dedo que só queria rolar a tela caía na alça e
// começava a arrastar. No toque o evento não chega ao Sortable (o vuedraggable), então rolar
// e tocar para abrir/fechar a seção funcionam e a ordem só muda pelo computador. O Kanban do
// CRM continua arrastando no toque, segurando o dedo um instante (KanbanBoard.vue).
const TOUCH_DRAG_HANDLES = '.drag-handle';
const blockTouchDrag = event => {
  if (event.type === 'pointerdown' && event.pointerType === 'mouse') return;
  const handle = event.target?.closest?.(TOUCH_DRAG_HANDLES);
  if (!handle || handle.closest('[data-outsider-touch-drag]')) return;
  event.stopPropagation();
};
const startTouchDragGuard = () => {
  const options = { capture: true, passive: true };
  document.addEventListener('pointerdown', blockTouchDrag, options);
  document.addEventListener('touchstart', blockTouchDrag, options);
  return () => {
    document.removeEventListener('pointerdown', blockTouchDrag, options);
    document.removeEventListener('touchstart', blockTouchDrag, options);
  };
};

export const useOutsiderResponsive = () => {
  const route = useRoute();
  const { uiSettings, updateUISettings } = useUISettings();

  setViewportMeta();
  document.documentElement.classList.toggle('outsider-touch', isTouch());
  const stopViewport = startViewportHeight();
  const stopTouchDragGuard = startTouchDragGuard();
  onBeforeUnmount(() => {
    stopViewport();
    stopTouchDragGuard();
  });

  // --- 2. painel do contato fechado ao entrar numa conversa pelo celular ----------------
  const closeContactPanelOnPhone = () => {
    if (window.innerWidth >= SMALL_SCREEN) return;
    if (!uiSettings.value?.is_contact_sidebar_open) return;
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  };
  watch(
    () => route.params.conversation_id,
    id => {
      if (id) closeContactPanelOnPhone();
    },
    { immediate: true }
  );
  // as preferências podem chegar depois do primeiro desenho da tela: vale o primeiro valor
  let settled = false;
  watch(
    () => uiSettings.value?.is_contact_sidebar_open,
    open => {
      if (settled) return;
      if (!Object.keys(uiSettings.value || {}).length) return;
      settled = true;
      if (open && route.params.conversation_id) closeContactPanelOnPhone();
    },
    { immediate: true }
  );
};
