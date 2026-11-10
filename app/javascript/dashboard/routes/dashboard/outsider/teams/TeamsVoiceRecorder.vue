<script setup>
// OUTSIDER: gravador de áudio da área Teams. Grava pelo microfone (pausar, continuar, descartar, enviar) e entrega o
// áudio em OGG/Opus (só reempacotado, instantâneo) para ir ao Teams como arquivo "Áudio de Fulano.ogg", que toca no
// Teams e aqui no player do Chatwoot. (A Microsoft não deixa outros aplicativos mandarem a mensagem de voz do celular.)
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { remuxWebmToOgg } from 'dashboard/components/widgets/WootWriter/utils/webmOpusToOgg';

const props = defineProps({ senderName: { type: String, default: '' } });
const emit = defineEmits(['send', 'close']);

const MAX_SECONDS = 10 * 60;
const { t } = useI18n();
const state = ref('recording'); // recording | paused | sending
const seconds = ref(0);
let recorder = null;
let stream = null;
let chunks = [];
let timer = null;
let startedAt = 0;
let elapsedBefore = 0;

const timeText = computed(() => {
  const mm = String(Math.floor(seconds.value / 60)).padStart(2, '0');
  const ss = String(seconds.value % 60).padStart(2, '0');
  return `${mm}:${ss}`;
});

const tick = () => {
  seconds.value = Math.floor((elapsedBefore + (Date.now() - startedAt)) / 1000);
  if (seconds.value >= MAX_SECONDS) send(); // eslint-disable-line no-use-before-define
};

const stopAll = () => {
  clearInterval(timer);
  timer = null;
  stream?.getTracks().forEach(track => track.stop());
  stream = null;
};

const mimeType = () =>
  ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus', 'audio/webm'].find(
    type => window.MediaRecorder?.isTypeSupported(type)
  ) || '';

const fileName = () => {
  const now = new Date();
  const pad = n => String(n).padStart(2, '0');
  const who = (props.senderName || 'voz').split(' ')[0];
  return `Áudio de ${who} ${pad(now.getDate())}-${pad(now.getMonth() + 1)} ${pad(now.getHours())}h${pad(now.getMinutes())}.ogg`;
};

const finish = async () => {
  stopAll();
  const raw = new Blob(chunks, { type: recorder?.mimeType || 'audio/webm' });
  chunks = [];
  if (!raw.size) {
    emit('close');
    return;
  }
  try {
    const ogg = await remuxWebmToOgg(raw);
    emit('send', new File([ogg], fileName(), { type: 'audio/ogg' }));
  } catch {
    useAlert(t('OUTSIDER_TEAMS_AREA.VOICE.FAILED'));
    emit('close');
  }
};

const start = async () => {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch {
    useAlert(t('OUTSIDER_TEAMS_AREA.VOICE.NO_MIC'));
    emit('close');
    return;
  }
  const type = mimeType();
  recorder = new MediaRecorder(stream, type ? { mimeType: type } : {});
  recorder.ondataavailable = event => {
    if (event.data?.size) chunks.push(event.data);
  };
  recorder.onstop = finish;
  recorder.start(250);
  startedAt = Date.now();
  timer = setInterval(tick, 250);
};

const pause = () => {
  if (recorder?.state !== 'recording') return;
  recorder.pause();
  elapsedBefore += Date.now() - startedAt;
  clearInterval(timer);
  state.value = 'paused';
};

const resume = () => {
  if (recorder?.state !== 'paused') return;
  recorder.resume();
  startedAt = Date.now();
  timer = setInterval(tick, 250);
  state.value = 'recording';
};

const send = () => {
  if (!recorder || state.value === 'sending') return;
  state.value = 'sending';
  if (recorder.state === 'inactive') finish();
  else recorder.stop();
};

const discard = () => {
  chunks = [];
  if (recorder && recorder.state !== 'inactive') {
    recorder.onstop = null;
    recorder.stop();
  }
  stopAll();
  emit('close');
};

onMounted(start);
onBeforeUnmount(() => {
  if (recorder && recorder.state !== 'inactive') {
    recorder.onstop = null;
    recorder.stop();
  }
  stopAll();
});
</script>

<template>
  <div
    class="flex items-center w-full gap-2 px-2 py-1.5 border rounded-full border-n-weak bg-n-alpha-1"
    data-teams-recorder
  >
    <button
      type="button"
      class="grid rounded-full size-9 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
      :title="t('OUTSIDER_TEAMS_AREA.VOICE.DISCARD')"
      @click="discard"
    >
      <Icon icon="i-lucide-trash-2" class="size-5" />
    </button>
    <span
      class="rounded-full size-2.5 shrink-0"
      :class="state === 'recording' ? 'bg-n-ruby-9 animate-pulse' : 'bg-n-slate-9'"
    />
    <span class="w-12 text-sm tabular-nums text-n-slate-12">{{ timeText }}</span>
    <span class="flex-1 text-xs truncate text-n-slate-11">
      {{
        state === 'paused'
          ? t('OUTSIDER_TEAMS_AREA.VOICE.PAUSED')
          : t('OUTSIDER_TEAMS_AREA.VOICE.RECORDING')
      }}
    </span>
    <button
      type="button"
      class="grid rounded-full size-9 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
      :title="state === 'paused' ? t('OUTSIDER_TEAMS_AREA.VOICE.RESUME') : t('OUTSIDER_TEAMS_AREA.VOICE.PAUSE')"
      @click="state === 'paused' ? resume() : pause()"
    >
      <Icon :icon="state === 'paused' ? 'i-lucide-mic' : 'i-lucide-pause'" class="size-5" />
    </button>
    <button
      type="button"
      class="grid rounded-full size-9 place-items-center tms-accent-bg disabled:opacity-40"
      :disabled="state === 'sending'"
      :title="t('OUTSIDER_TEAMS_AREA.SEND')"
      data-teams-voice-send
      @click="send"
    >
      <Icon icon="i-lucide-send-horizontal" class="size-[18px]" />
    </button>
  </div>
</template>
