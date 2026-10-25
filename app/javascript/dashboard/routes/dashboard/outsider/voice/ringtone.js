// OUTSIDER: tons do telefone (Entrega 22), gerados pelo navegador, sem arquivo de áudio. "incoming": a ligação
// que chega (dois tons por 1,2 s a cada 3 s). "ringback": o "chamando" de quem liga (425 Hz por 1 s a cada
// 5 s, o padrão brasileiro), enquanto o outro lado não manda o próprio som.
const TONES = {
  incoming: { frequencies: [440, 480], seconds: 1.2, every: 3000, volume: 0.2 },
  ringback: { frequencies: [425], seconds: 1, every: 5000, volume: 0.1 },
};

let context = null;
let timer = null;
let gain = null;

const beep = ({ frequencies, seconds, volume }) => {
  const now = context.currentTime;
  gain = context.createGain();
  gain.gain.setValueAtTime(0.0001, now);
  gain.gain.exponentialRampToValueAtTime(volume, now + 0.05);
  gain.gain.setValueAtTime(volume, now + seconds - 0.05);
  gain.gain.exponentialRampToValueAtTime(0.0001, now + seconds);
  gain.connect(context.destination);
  frequencies.forEach(frequency => {
    const tone = context.createOscillator();
    tone.frequency.value = frequency;
    tone.connect(gain);
    tone.start(now);
    tone.stop(now + seconds);
  });
};

// corta na hora, sem esperar o tom que está tocando acabar
export const stopTone = () => {
  clearInterval(timer);
  timer = null;
  if (!gain) return;
  gain.gain.cancelScheduledValues(context.currentTime);
  gain.gain.setValueAtTime(0.0001, context.currentTime);
  gain = null;
};

export const startTone = name => {
  stopTone();
  const tone = TONES[name];
  context = context || new AudioContext();
  context.resume();
  beep(tone);
  timer = setInterval(() => beep(tone), tone.every);
};
