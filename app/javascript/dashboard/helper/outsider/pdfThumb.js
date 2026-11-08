// OUTSIDER: a primeira página de um PDF como imagem pequena (miniatura do cartão do documento), desenhada no próprio
// navegador com o pdf.js, que só é baixado quando aparece o primeiro PDF. Desenha só o alto da página, guarda o
// resultado na memória e na sessão do navegador (não baixa de novo ao voltar à conversa) e faz no máximo 2 por vez.
const STORE = 'outsider-pdf-thumb:';
const RUNNING_MAX = 2;
const memory = new Map();
const waiting = [];
let running = 0;
let library = null;

const loadLibrary = () => {
  if (!library) {
    library = Promise.all([
      import('pdfjs-dist/legacy/build/pdf.mjs'),
      import('pdfjs-dist/legacy/build/pdf.worker.min.mjs?worker'),
    ]).then(([lib, worker]) => {
      // um worker só para todas as miniaturas (o Vite empacota o worker do pdf.js junto)
      const PdfWorker = worker.default;
      lib.GlobalWorkerOptions.workerPort = new PdfWorker();
      return lib;
    });
    library.catch(() => {
      library = null;
    });
  }
  return library;
};

const queued = task =>
  new Promise((resolve, reject) => {
    const run = async () => {
      running += 1;
      try {
        resolve(await task());
      } catch (error) {
        reject(error);
      } finally {
        running -= 1;
        waiting.shift()?.();
      }
    };
    if (running < RUNNING_MAX) run();
    else waiting.push(run);
  });

const readStored = key => {
  try {
    return JSON.parse(window.sessionStorage.getItem(STORE + key) || 'null');
  } catch (error) {
    return null;
  }
};

const writeStored = (key, value) => {
  try {
    window.sessionStorage.setItem(STORE + key, JSON.stringify(value));
  } catch (error) {
    // sessão cheia ou bloqueada: fica só na memória
  }
};

const render = async (source, width) => {
  const lib = await loadLibrary();
  const url = typeof source === 'function' ? await source() : source;
  const doc = await lib.getDocument({ url, isEvalSupported: false }).promise;
  try {
    const page = await doc.getPage(1);
    const base = page.getViewport({ scale: 1 });
    const viewport = page.getViewport({ scale: (width * 2) / base.width });
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(viewport.width);
    canvas.height = Math.ceil(Math.min(viewport.height, viewport.width * 0.75));
    const context = canvas.getContext('2d');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: context, viewport }).promise;
    return { src: canvas.toDataURL('image/jpeg', 0.82), pages: doc.numPages };
  } finally {
    doc.destroy();
  }
};

// key: o que identifica o arquivo (id do anexo); source: endereço do PDF no próprio Chatwoot, ou função que o busca
// (só chamada quando a miniatura ainda não está guardada)
export const pdfThumb = (key, source, width = 320) => {
  if (memory.has(key)) return memory.get(key);
  const stored = readStored(key);
  const job = stored?.src
    ? Promise.resolve(stored)
    : queued(() => render(source, width)).then(result => {
        writeStored(key, result);
        return result;
      });
  memory.set(key, job);
  job.catch(() => memory.delete(key));
  return job;
};
