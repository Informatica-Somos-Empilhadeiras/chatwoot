// OUTSIDER: apoio do player de áudio estilo WhatsApp (components-next/message/outsider/VoicePlayer.vue).
// - onda: lida do próprio arquivo (Web Audio) e guardada por endereço enquanto a página está aberta.
//   Quando o arquivo não pode ser lido daqui (ex.: o Dev abrindo um anexo da produção), a onda é
//   desenhada a partir do id do anexo, sempre igual para o mesmo áudio.
// - ouvido: o microfone fica azul depois que alguém deste navegador tocou o áudio (como no
//   WhatsApp); a lista fica no navegador.
// - velocidade: a última escolhida vale para os próximos áudios.
import { splitSenderHeader } from './mediaAlbum';

export const BAR_COUNT = 44;
export const SPEEDS = [1, 1.5, 2];

const PLAYED_KEY = 'outsider_voice_played';
const SPEED_KEY = 'outsider_voice_speed';
const MAX_PLAYED = 500;

const waveforms = new Map();

const readStorage = (key, fallback) => {
  try {
    const value = window.localStorage.getItem(key);
    return value ? JSON.parse(value) : fallback;
  } catch {
    return fallback;
  }
};

const writeStorage = (key, value) => {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // sem armazenamento (aba anônima): só não lembra
  }
};

// onda estável a partir de um número (id do anexo)
export const placeholderWaveform = (seed, count = BAR_COUNT) => {
  let state = (Number(seed) || 1) % 2147483647;
  if (state <= 0) state += 2147483646;
  return Array.from({ length: count }, (_, index) => {
    state = (state * 16807) % 2147483647;
    const noise = (state - 1) / 2147483646;
    const envelope = Math.sin((Math.PI * (index + 1)) / (count + 1));
    return Math.max(0.12, Math.min(1, 0.25 + noise * 0.55 + envelope * 0.25));
  });
};

const peaksOf = (buffer, count) => {
  const data = buffer.getChannelData(0);
  const size = Math.max(1, Math.floor(data.length / count));
  const peaks = Array.from({ length: count }, (_, bar) => {
    let sum = 0;
    const start = bar * size;
    const end = Math.min(data.length, start + size);
    for (let i = start; i < end; i += 1) sum += data[i] * data[i];
    return Math.sqrt(sum / Math.max(1, end - start));
  });
  const max = Math.max(...peaks) || 1;
  return peaks.map(peak => Math.max(0.08, peak / max));
};

const decode = async (url, count) => {
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return null;
  const response = await fetch(url, { credentials: 'same-origin' });
  if (!response.ok) return null;
  const context = new AudioContextClass();
  try {
    const buffer = await context.decodeAudioData(await response.arrayBuffer());
    return { bars: peaksOf(buffer, count), duration: buffer.duration };
  } finally {
    context.close?.();
  }
};

export const loadWaveform = (url, count = BAR_COUNT) => {
  if (!url) return Promise.resolve(null);
  if (!waveforms.has(url)) {
    waveforms.set(
      url,
      decode(url, count).catch(() => null)
    );
  }
  return waveforms.get(url);
};

export const wasPlayed = id => readStorage(PLAYED_KEY, []).includes(id);

export const markPlayed = id => {
  const played = readStorage(PLAYED_KEY, []).filter(item => item !== id);
  played.push(id);
  writeStorage(PLAYED_KEY, played.slice(-MAX_PLAYED));
};

export const savedSpeed = () => {
  const speed = Number(readStorage(SPEED_KEY, 1));
  return SPEEDS.includes(speed) ? speed : 1;
};

export const saveSpeed = speed => writeStorage(SPEED_KEY, speed);

export const formatClock = seconds => {
  if (!Number.isFinite(seconds) || seconds < 0) return '0:00';
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
};

// áudio de grupo: a Evolution põe quem enviou no texto ("**+55 ... - Nome:**"); sem outra legenda,
// continua sendo uma mensagem de voz
export const isVoiceWithHeader = ({
  content,
  attachments,
  private: isPrivate,
} = {}) =>
  !isPrivate &&
  Array.isArray(attachments) &&
  attachments.length === 1 &&
  attachments[0].fileType === 'audio' &&
  !!content &&
  !splitSenderHeader(content).body &&
  !!splitSenderHeader(content).header;
