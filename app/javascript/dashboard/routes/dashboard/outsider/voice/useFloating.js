// OUTSIDER: o telefone solto na tela (Entrega 24). Arrastando pelo topo, ele vai para onde a pessoa quiser e
// fica lá (o navegador lembra); dois cliques no topo voltam para o canto. A posição é a distância do canto
// inferior direito, e nunca deixa o telefone sair da tela, mesmo quando a janela diminui.
import { computed } from 'vue';
import { useWindowSize, useElementSize } from '@vueuse/core';
import { panel, setPanelPosition } from './phone';

const GAP = 16;
const EDGE = 8;
// no celular (abaixo de 640 px) o telefone ocupa a largura toda, colado embaixo (ou em cima, para o
// cartão da ligação não cobrir a caixa de texto), e não arrasta: o dedo rola o conteúdo dele
const PHONE_WIDTH = 640;

export const useFloating = (element, { phoneEdge = 'bottom' } = {}) => {
  const { width: windowWidth, height: windowHeight } = useWindowSize();
  const isPhone = computed(() => windowWidth.value < PHONE_WIDTH);
  const { width, height } = useElementSize(element, undefined, {
    box: 'border-box',
  });

  const clamp = ({ right, bottom }) => ({
    right: Math.min(
      Math.max(EDGE, right),
      Math.max(EDGE, windowWidth.value - width.value - EDGE)
    ),
    bottom: Math.min(
      Math.max(EDGE, bottom),
      Math.max(EDGE, windowHeight.value - height.value - EDGE)
    ),
  });

  const style = computed(() => {
    if (isPhone.value) {
      return phoneEdge === 'top'
        ? { left: '0px', right: '0px', top: '0px' }
        : { left: '0px', right: '0px', bottom: '0px' };
    }
    const { right, bottom } = clamp(
      panel.position || { right: GAP, bottom: GAP }
    );
    return { right: `${right}px`, bottom: `${bottom}px` };
  });

  // botões e campos do topo continuam clicáveis: só arrasta pelo fundo
  const startDrag = event => {
    if (isPhone.value) return;
    if (event.button !== 0 || event.target.closest('button, input, a')) return;
    const start = { x: event.clientX, y: event.clientY };
    const origin = clamp(panel.position || { right: GAP, bottom: GAP });
    let moved = false;
    const move = moveEvent => {
      moved = true;
      panel.position = clamp({
        right: origin.right - (moveEvent.clientX - start.x),
        bottom: origin.bottom - (moveEvent.clientY - start.y),
      });
    };
    const stop = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', stop);
      document.body.style.userSelect = '';
      if (moved) setPanelPosition(panel.position);
    };
    document.body.style.userSelect = 'none';
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', stop);
  };

  const resetPosition = () => setPanelPosition(null);

  return { style, startDrag, resetPosition, isPhone };
};
