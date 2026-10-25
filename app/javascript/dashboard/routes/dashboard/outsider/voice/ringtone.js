// OUTSIDER: toque da ligação que chega (Entrega 22), gerado pelo navegador, sem arquivo de áudio: dois tons
// por 1,2 s a cada 3 s, até atender, recusar ou a central desistir.
let context = null;
let timer = null;

const beep = () => {
  const now = context.currentTime;
  const gain = context.createGain();
  gain.gain.setValueAtTime(0.0001, now);
  gain.gain.exponentialRampToValueAtTime(0.2, now + 0.05);
  gain.gain.setValueAtTime(0.2, now + 1.15);
  gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.2);
  gain.connect(context.destination);
  [440, 480].forEach(frequency => {
    const tone = context.createOscillator();
    tone.frequency.value = frequency;
    tone.connect(gain);
    tone.start(now);
    tone.stop(now + 1.2);
  });
};

export const startRinging = () => {
  if (timer) return;
  context = context || new AudioContext();
  context.resume();
  beep();
  timer = setInterval(beep, 3000);
};

export const stopRinging = () => {
  clearInterval(timer);
  timer = null;
};
