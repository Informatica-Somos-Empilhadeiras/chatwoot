<script setup>
// OUTSIDER: barras que sobem e descem com a voz (Entrega 23): o volume do áudio (microfone da pessoa ou som
// do outro lado) medido pelo navegador várias vezes por segundo. Sem áudio, ficam baixinhas.
import { ref, watch, onBeforeUnmount } from 'vue';

const props = defineProps({
  stream: { type: Object, default: null },
  // cor das barras (classe do Tailwind)
  color: { type: String, default: 'bg-n-teal-9' },
});

// cada barra reage um pouco diferente, para parecer um equalizador
const WEIGHTS = [0.55, 0.85, 1, 0.75, 0.5];
const levels = ref(WEIGHTS.map(() => 0));

let context = null;
let source = null;
let frame = null;

const stop = () => {
  cancelAnimationFrame(frame);
  source?.disconnect();
  context?.close();
  context = null;
  source = null;
  levels.value = WEIGHTS.map(() => 0);
};

const start = stream => {
  stop();
  if (!stream?.getAudioTracks().length) return;
  context = new AudioContext();
  const analyser = context.createAnalyser();
  analyser.fftSize = 256;
  source = context.createMediaStreamSource(stream);
  source.connect(analyser);
  const samples = new Uint8Array(analyser.fftSize);
  const tick = () => {
    analyser.getByteTimeDomainData(samples);
    let sum = 0;
    samples.forEach(sample => {
      const value = (sample - 128) / 128;
      sum += value * value;
    });
    const volume = Math.min(1, Math.sqrt(sum / samples.length) * 4);
    levels.value = WEIGHTS.map(weight => volume * weight);
    frame = requestAnimationFrame(tick);
  };
  tick();
};

watch(() => props.stream, start, { immediate: true });
onBeforeUnmount(stop);
</script>

<template>
  <span class="inline-flex items-center gap-0.5 h-5" aria-hidden="true">
    <span
      v-for="(level, index) in levels"
      :key="index"
      class="w-1 rounded-full transition-[height] duration-75"
      :class="color"
      :style="{ height: `${Math.max(15, level * 100)}%` }"
    />
  </span>
</template>
