// OUTSIDER: soltar arquivos em qualquer lugar do chat/canal aberto do Teams. Enquanto arrasta aparece o aviso
// "Solte para anexar" por cima da conversa; ao soltar, os arquivos vão para a caixa de escrever (addFiles).
// Só reage a arquivos (arrastar texto ou uma foto da própria conversa não mostra o aviso).
import { ref } from 'vue';

const hasFiles = event =>
  Array.from(event.dataTransfer?.types || []).includes('Files');

export const useTeamsDrop = (onFiles, isEnabled = () => true) => {
  const dragging = ref(false);
  let depth = 0;

  const reset = () => {
    depth = 0;
    dragging.value = false;
  };

  const onDragenter = event => {
    if (!hasFiles(event) || !isEnabled()) return;
    event.preventDefault();
    depth += 1;
    dragging.value = true;
  };
  const onDragover = event => {
    if (!hasFiles(event) || !isEnabled()) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
  };
  const onDragleave = event => {
    if (!hasFiles(event)) return;
    depth = Math.max(0, depth - 1);
    if (!depth) dragging.value = false;
  };
  const onDrop = event => {
    if (!hasFiles(event)) return;
    event.preventDefault();
    reset();
    if (isEnabled()) onFiles(event.dataTransfer.files);
  };

  return {
    dragging,
    dropHandlers: {
      dragenter: onDragenter,
      dragover: onDragover,
      dragleave: onDragleave,
      drop: onDrop,
    },
  };
};
