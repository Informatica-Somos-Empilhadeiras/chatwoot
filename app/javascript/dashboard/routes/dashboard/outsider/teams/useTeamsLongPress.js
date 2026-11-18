// OUTSIDER: segurar o dedo numa mensagem (celular/tablet) abre o menu dela, como no WhatsApp e no Teams do celular.
// Só para toque: com mouse continuam os botões que aparecem ao passar o mouse. Arrastar (rolar a conversa) cancela.
// Depois de abrir o menu, o toque não vira clique (não abre a foto nem o link que estava embaixo do dedo).
const HOLD_MS = 450;
const MOVE_PX = 10;

export const useTeamsLongPress = onPress => {
  let timer = null;
  let start = null;
  let fired = false;

  const cancel = () => {
    clearTimeout(timer);
    timer = null;
  };

  const handlers = target => ({
    pointerdown: event => {
      if (event.pointerType === 'mouse') return;
      fired = false;
      start = { x: event.clientX, y: event.clientY };
      cancel();
      timer = setTimeout(() => {
        fired = true;
        timer = null;
        navigator.vibrate?.(15);
        onPress(target);
      }, HOLD_MS);
    },
    pointermove: event => {
      if (!timer || !start) return;
      const moved =
        Math.abs(event.clientX - start.x) > MOVE_PX ||
        Math.abs(event.clientY - start.y) > MOVE_PX;
      if (moved) cancel();
    },
    pointerup: cancel,
    pointercancel: cancel,
    // menu do navegador (copiar imagem, abrir link...) não aparece por cima do nosso
    contextmenu: event => {
      if (event.pointerType === 'mouse' || (!fired && !timer)) return;
      event.preventDefault();
    },
  });

  // vai no @click.capture do mesmo elemento
  const swallowClick = event => {
    if (!fired) return;
    fired = false;
    event.preventDefault();
    event.stopPropagation();
  };

  return { handlers, swallowClick };
};
