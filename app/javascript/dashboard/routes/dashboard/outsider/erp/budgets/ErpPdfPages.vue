<script setup>
// OUTSIDER: as páginas de um PDF desenhadas com o pdf.js (o mesmo leitor do Nextcloud) na resolução da tela, para o PDF
// ficar igual em qualquer navegador: o leitor embutido do Chrome/Brave desenha mal as barras finas do código de barras
// do DANFE (umas engrossam, outras somem). zoom 1 = largura da área. Se o pdf.js não abrir o arquivo, avisa (failed)
// para quem usa cair no leitor do navegador.
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { loadPdfLibrary } from 'dashboard/helper/outsider/pdfThumb';

const props = defineProps({
  file: { type: Blob, required: true },
  zoom: { type: Number, default: 1 },
});

const emit = defineEmits(['failed']);

const pagesRef = ref(null);
let doc = null;
let drawing = 0;

const drawPage = async (number, token, width) => {
  if (token !== drawing) return;
  const page = await doc.getPage(number);
  const base = page.getViewport({ scale: 1 });
  const viewport = page.getViewport({
    scale: (width / base.width) * (window.devicePixelRatio || 1),
  });
  const canvas = document.createElement('canvas');
  canvas.width = Math.floor(viewport.width);
  canvas.height = Math.floor(viewport.height);
  // a largura na tela é a do desenho dividida pela densidade da tela: um pixel do desenho por pixel da tela
  canvas.style.width = `${width}px`;
  canvas.className = 'mx-auto bg-white shadow-sm shrink-0';
  pagesRef.value?.appendChild(canvas);
  await page.render({ canvasContext: canvas.getContext('2d'), viewport })
    .promise;
};

// desenha página por página; um zoom novo no meio do caminho interrompe o desenho anterior
const draw = async () => {
  drawing += 1;
  const token = drawing;
  const box = pagesRef.value;
  if (!doc || !box) return;
  box.replaceChildren();
  const width = Math.floor((box.clientWidth - 32) * props.zoom);
  const pages = Array.from({ length: doc.numPages }, (_, index) => index + 1);
  try {
    await pages.reduce(
      (chain, number) => chain.then(() => drawPage(number, token, width)),
      Promise.resolve()
    );
  } catch {
    emit('failed');
  }
};

const load = async () => {
  try {
    const lib = await loadPdfLibrary();
    doc?.destroy();
    doc = await lib.getDocument({
      data: new Uint8Array(await props.file.arrayBuffer()),
      isEvalSupported: false,
    }).promise;
    await draw();
  } catch {
    emit('failed');
  }
};

onMounted(load);
watch(() => props.file, load);
watch(() => props.zoom, draw);

onBeforeUnmount(() => {
  drawing += 1;
  doc?.destroy();
  doc = null;
});
</script>

<template>
  <div ref="pagesRef" class="flex flex-col h-full gap-3 p-4 overflow-auto" />
</template>
