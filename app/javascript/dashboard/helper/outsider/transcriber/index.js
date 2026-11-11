// OUTSIDER: transcrição de áudio no navegador do agente (Whisper em WebAssembly/WebGPU, ver whisper.worker.js).
// Aqui fica a parte que precisa da tela: baixar o arquivo, decodificar para 16 kHz mono (Web Audio), cortar em
// pedaços de até 30 s nos silêncios e mandar para o worker, acompanhando o progresso. Uma fila: um áudio por vez.
/* global axios */
import { reactive } from 'vue';

export const MODEL_SIZES = ['rapido', 'preciso'];
const SIZE_KEY = 'outsider_transcricao_modelo';
const SAMPLE_RATE = 16000;
const PIECE_SECONDS = 30;
const CUT_WINDOW_SECONDS = 6; // procura o silêncio nos últimos 6 s de cada pedaço
export const MAX_SECONDS = 20 * 60;

export const savedSize = () => {
  try {
    const value = localStorage.getItem(SIZE_KEY);
    return MODEL_SIZES.includes(value) ? value : 'preciso';
  } catch {
    return 'preciso';
  }
};

export const saveSize = size => {
  try {
    localStorage.setItem(SIZE_KEY, size);
  } catch {
    // navegador sem armazenamento: segue com o padrão
  }
};

export const canTranscribe = () =>
  typeof window !== 'undefined' &&
  !!window.Worker &&
  !!(window.AudioContext || window.webkitAudioContext) &&
  !!window.OfflineAudioContext;

// estado por áudio (chave = id do anexo), lido pelos botões
export const jobs = reactive({});

let worker = null;
let queue = Promise.resolve();
let nextId = 1;
const waiting = {};

const getWorker = () => {
  if (worker) return worker;
  worker = new Worker(new URL('./whisper.worker.js', import.meta.url), {
    type: 'module',
  });
  worker.onmessage = event => {
    const data = event.data || {};
    const job = waiting[data.jobId];
    if (!job) return;
    if (data.type === 'progress') {
      job.onProgress(data);
    } else if (data.type === 'done') {
      delete waiting[data.jobId];
      job.resolve(data);
    } else if (data.type === 'error') {
      delete waiting[data.jobId];
      job.reject(new Error(data.message || 'worker'));
    }
  };
  worker.onerror = event => {
    Object.values(waiting).forEach(job =>
      job.reject(new Error(event.message || 'worker'))
    );
    Object.keys(waiting).forEach(key => delete waiting[key]);
    worker = null;
  };
  return worker;
};

// pelo axios do Chatwoot: leva o login da API (o fetch simples não leva)
const fetchAudio = async url => {
  try {
    const { data } = await axios.get(url, { responseType: 'arraybuffer' });
    return data;
  } catch {
    throw new Error('download');
  }
};

// decodifica qualquer formato que o navegador toque e entrega mono em 16 kHz
const decode = async buffer => {
  const Context = window.AudioContext || window.webkitAudioContext;
  const context = new Context();
  try {
    const decoded = await context.decodeAudioData(buffer.slice(0));
    if (decoded.duration > MAX_SECONDS) throw new Error('too_long');
    const length = Math.ceil(decoded.duration * SAMPLE_RATE);
    const offline = new OfflineAudioContext(1, length, SAMPLE_RATE);
    const source = offline.createBufferSource();
    source.buffer = decoded;
    source.connect(offline.destination);
    source.start(0);
    const rendered = await offline.startRendering();
    return { audio: rendered.getChannelData(0), duration: decoded.duration };
  } finally {
    context.close().catch(() => {});
  }
};

// energia média por janelas de 100 ms, para achar o ponto mais calmo onde cortar
const quietestCut = (audio, from, to) => {
  const step = SAMPLE_RATE / 10;
  let best = to;
  let bestEnergy = Infinity;
  for (let start = from; start + step <= to; start += step) {
    let sum = 0;
    for (let i = start; i < start + step; i += 1) sum += audio[i] * audio[i];
    if (sum < bestEnergy) {
      bestEnergy = sum;
      best = start + step / 2;
    }
  }
  return Math.round(best);
};

export const splitPieces = audio => {
  const pieces = [];
  const pieceLength = PIECE_SECONDS * SAMPLE_RATE;
  let offset = 0;
  while (offset < audio.length) {
    let end = Math.min(audio.length, offset + pieceLength);
    if (end < audio.length) {
      end = quietestCut(audio, end - CUT_WINDOW_SECONDS * SAMPLE_RATE, end);
    }
    pieces.push({
      audio: audio.slice(offset, end),
      offset: offset / SAMPLE_RATE,
    });
    offset = end;
  }
  return pieces;
};

const runInWorker = (pieces, size, language, onProgress) =>
  new Promise((resolve, reject) => {
    const jobId = nextId;
    nextId += 1;
    waiting[jobId] = { resolve, reject, onProgress };
    getWorker().postMessage(
      { type: 'run', jobId, size, language, pieces },
      pieces.map(piece => piece.audio.buffer)
    );
  });

const setJob = (key, patch) => {
  jobs[key] = { ...(jobs[key] || {}), ...patch };
};

// transcribe({ key, url, language }) -> { text, segments, duration, model, device }
// Progresso em jobs[key]: { status: 'fila'|'lendo'|'baixando'|'carregando'|'transcrevendo'|'pronto'|'erro', percent, partial, error }
export const transcribe = ({ key, url, language = 'portuguese' }) => {
  const size = savedSize();
  setJob(key, { status: 'fila', percent: 0, partial: '', error: '' });
  const task = async () => {
    try {
      // gancho de teste: um transcritor simulado injetado pela página (sem baixar modelo)
      if (window.outsiderWhisperFake) {
        setJob(key, { status: 'transcrevendo', percent: 50 });
        const fake = await window.outsiderWhisperFake({ key, url, size });
        setJob(key, { status: 'pronto', percent: 100 });
        return fake;
      }
      setJob(key, { status: 'lendo', percent: 0 });
      const buffer = await fetchAudio(url);
      const { audio, duration } = await decode(buffer).catch(error => {
        throw new Error(
          error?.message === 'too_long' ? 'too_long' : 'download'
        );
      });
      const pieces = splitPieces(audio);
      const result = await runInWorker(pieces, size, language, data => {
        setJob(key, {
          status: data.phase,
          percent: data.percent,
          partial: data.partial || jobs[key]?.partial || '',
        });
      });
      setJob(key, { status: 'pronto', percent: 100 });
      return { ...result, duration, size };
    } catch (error) {
      const code = String(error?.message || 'erro');
      setJob(key, { status: 'erro', error: code });
      throw error;
    }
  };
  const result = queue.then(task, task);
  queue = result.catch(() => {});
  return result;
};

export const clearJob = key => {
  delete jobs[key];
};
