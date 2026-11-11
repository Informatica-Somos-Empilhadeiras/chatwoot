/* global globalThis */
// OUTSIDER: transcrição no navegador. Roda num Web Worker para não travar a tela: carrega o Whisper (modelo aberto
// da OpenAI em ONNX, via transformers.js) e transcreve trechos de áudio já decodificados em 16 kHz mono.
// O modelo é baixado do Hugging Face na primeira vez e fica no cache do navegador; o motor WebAssembly/WebGPU
// vem do jsDelivr (padrão da biblioteca). Nada de áudio sai do computador do agente.
import { pipeline, env } from '@huggingface/transformers';

env.allowLocalModels = false;

// rapido: whisper-base (~60 MB em q8), preciso: whisper-small (~190 MB em q8); os dois sabem português
const MODELS = {
  rapido: ['onnx-community/whisper-base', 'Xenova/whisper-base'],
  preciso: ['onnx-community/whisper-small', 'Xenova/whisper-small'],
};

let current = { key: '', promise: null };

const post = data => globalThis.postMessage(data);

const hasWebGPU = async () => {
  try {
    if (!globalThis.navigator?.gpu) return false;
    const adapter = await globalThis.navigator.gpu.requestAdapter();
    return !!adapter;
  } catch {
    return false;
  }
};

const load = async (size, jobId) => {
  const key = size;
  if (current.key === key && current.promise) return current.promise;
  const names = MODELS[size] || MODELS.preciso;
  const webgpu = await hasWebGPU();
  const options = webgpu
    ? {
        device: 'webgpu',
        dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' },
      }
    : { device: 'wasm', dtype: 'q8' };
  const files = {};
  const progress = event => {
    if (event.status === 'progress' && event.file) {
      files[event.file] = {
        loaded: event.loaded || 0,
        total: event.total || 0,
      };
      const totals = Object.values(files);
      const loaded = totals.reduce((sum, item) => sum + item.loaded, 0);
      const total = totals.reduce((sum, item) => sum + item.total, 0);
      post({
        type: 'progress',
        jobId,
        phase: 'baixando',
        percent: total ? Math.round((loaded / total) * 100) : 0,
      });
    } else if (event.status === 'ready' || event.status === 'done') {
      post({ type: 'progress', jobId, phase: 'carregando', percent: 100 });
    }
  };
  current = {
    key,
    // tenta o primeiro nome; se não existir, o seguinte
    promise: names.reduce(
      (previous, name) =>
        previous.catch(() =>
          pipeline('automatic-speech-recognition', name, {
            ...options,
            progress_callback: progress,
          }).then(transcriber => ({
            transcriber,
            name,
            device: options.device,
          }))
        ),
      Promise.reject(new Error('model'))
    ),
  };
  current.promise.catch(() => {
    current = { key: '', promise: null };
  });
  return current.promise;
};

const run = async ({ jobId, size, language, pieces }) => {
  let loaded;
  try {
    loaded = await load(size, jobId);
  } catch {
    // sem rede para o Hugging Face / jsDelivr, ou navegador sem suporte
    throw new Error('model');
  }
  const texts = [];
  const segments = [];
  for (let index = 0; index < pieces.length; index += 1) {
    const piece = pieces[index];
    post({
      type: 'progress',
      jobId,
      phase: 'transcrevendo',
      percent: Math.round((index / pieces.length) * 100),
      partial: texts.join(' ').trim(),
    });
    // eslint-disable-next-line no-await-in-loop
    const result = await loaded.transcriber(piece.audio, {
      language: language || 'portuguese',
      task: 'transcribe',
      chunk_length_s: 30,
      stride_length_s: 5,
      return_timestamps: true,
    });
    const text = (result?.text || '').trim();
    if (text) texts.push(text);
    (result?.chunks || []).forEach(chunk => {
      const [start, end] = chunk.timestamp || [];
      segments.push({
        start: Math.round(((start || 0) + piece.offset) * 10) / 10,
        end: end == null ? null : Math.round((end + piece.offset) * 10) / 10,
        text: (chunk.text || '').trim(),
      });
    });
  }
  post({
    type: 'done',
    jobId,
    text: texts.join(' ').replace(/\s+/g, ' ').trim(),
    segments,
    model: loaded.name,
    device: loaded.device,
  });
};

globalThis.onmessage = async event => {
  const data = event.data || {};
  if (data.type !== 'run') return;
  try {
    await run(data);
  } catch (error) {
    post({
      type: 'error',
      jobId: data.jobId,
      message: String(error?.message || error).slice(0, 300),
    });
  }
};
