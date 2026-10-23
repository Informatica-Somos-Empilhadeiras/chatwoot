<script setup>
// OUTSIDER: gravador de áudio estilo WhatsApp na caixa de resposta.
// Gravando: descartar, pausar ou enviar. Pausado: ouvir o que já foi gravado,
// continuar gravando, descartar ou enviar. "Enviar" manda só o áudio, como
// mensagem de voz; o texto digitado continua na caixa.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import getUuid from 'widget/helpers/uuid';
import { useAlert } from 'dashboard/composables';
import { useFileUpload } from 'dashboard/composables/useFileUpload';
import { convertAudio } from 'dashboard/components/widgets/WootWriter/utils/audioConversionUtils';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  audioRecordFormat: { type: String, required: true },
  inbox: { type: Object, required: true },
});

const emit = defineEmits(['send', 'close']);

const { t } = useI18n();

const RECORDING = 'recording';
const PAUSED = 'paused';
const SENDING = 'sending';
const EXTENSIONS = {
  'audio/ogg': 'ogg',
  'audio/mp3': 'mp3',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/webm': 'webm',
};
const WAVE_STYLE = {
  height: 32,
  barWidth: 3,
  barGap: 2,
  barRadius: 3,
  cursorWidth: 0,
};

const liveWave = ref(null);
const previewWave = ref(null);
const state = ref(RECORDING);
const durationMs = ref(0);
const isPlaying = ref(false);

// onda ao vivo (com o plugin de gravação) e onda do trecho gravado, para ouvir na pausa
let recorder = null;
let record = null;
let preview = null;
let previewUrl = null;

const { onFileUpload } = useFileUpload({
  inbox: props.inbox,
  attachFile: ({ file, blob }) =>
    emit('send', {
      files: [blob ? blob.signed_id : file.file],
      isVoiceMessage: true,
    }),
});

const timeText = computed(() => {
  const seconds = Math.floor(durationMs.value / 1000);
  const mm = String(Math.floor(seconds / 60)).padStart(2, '0');
  const ss = String(seconds % 60).padStart(2, '0');
  return `${mm}:${ss}`;
});

const destroyPreview = () => {
  preview?.destroy();
  preview = null;
  if (previewUrl) URL.revokeObjectURL(previewUrl);
  previewUrl = null;
  isPlaying.value = false;
};

const showPreview = blob => {
  destroyPreview();
  previewUrl = URL.createObjectURL(blob);
  preview = WaveSurfer.create({
    container: previewWave.value,
    url: previewUrl,
    waveColor: '#8696a0',
    progressColor: '#00a884',
    ...WAVE_STYLE,
  });
  preview.on('play', () => {
    isPlaying.value = true;
  });
  preview.on('pause', () => {
    isPlaying.value = false;
  });
};

const uploadRecording = async blob => {
  try {
    const audio = await convertAudio(blob, props.audioRecordFormat);
    const type = audio.type || props.audioRecordFormat;
    const name = `${getUuid()}.${EXTENSIONS[type] || 'mp3'}`;
    const file = new File([audio], name, { type });
    onFileUpload({ name, type, size: file.size, file, isVoiceMessage: true });
  } catch (error) {
    useAlert(t('CONVERSATION.REPLYBOX.AUDIO_CONVERSION_FAILED'));
    emit('close');
  }
};

const pause = () => {
  record.pauseRecording();
  state.value = PAUSED;
};

const resume = () => {
  destroyPreview();
  record.resumeRecording();
  state.value = RECORDING;
};

const send = () => {
  preview?.pause();
  state.value = SENDING;
  record.stopRecording();
};

const togglePlay = () => preview?.playPause();

onMounted(async () => {
  const options = { scrollingWaveform: true, renderRecordedAudio: false };
  if (
    props.audioRecordFormat === 'audio/ogg' &&
    MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')
  ) {
    options.mimeType = 'audio/ogg;codecs=opus';
  }

  recorder = WaveSurfer.create({
    container: liveWave.value,
    waveColor: '#00a884',
    progressColor: '#00a884',
    interact: false,
    ...WAVE_STYLE,
  });
  record = recorder.registerPlugin(RecordPlugin.create(options));
  record.on('record-progress', ms => {
    durationMs.value = ms;
  });
  record.on('record-pause', showPreview);
  // ao descartar, o destroy também encerra a gravação: só envia se pediu
  record.on('record-end', blob => {
    if (state.value === SENDING) uploadRecording(blob);
  });

  try {
    await record.startRecording();
  } catch (error) {
    useAlert(t('OUTSIDER_WHATSAPP.COMPOSER.MIC_ERROR'));
    emit('close');
  }
});

onBeforeUnmount(() => {
  destroyPreview();
  recorder?.destroy();
});
</script>

<template>
  <div
    class="flex items-center w-full gap-2 px-1.5 py-1.5 my-1 border rounded-3xl bg-white dark:bg-[#2A2F32] border-n-strong"
  >
    <NextButton
      v-tooltip.top="$t('OUTSIDER_WHATSAPP.COMPOSER.DISCARD')"
      icon="i-ph-trash"
      slate
      ghost
      class="!rounded-full flex-shrink-0 [&>span]:size-5"
      @click="emit('close')"
    />

    <div
      v-show="state !== PAUSED"
      class="flex items-center flex-1 min-w-0 gap-2"
    >
      <span
        class="flex-shrink-0 rounded-full size-2.5 bg-n-ruby-9"
        :class="{ 'animate-pulse': state === RECORDING }"
      />
      <span class="flex-shrink-0 w-12 text-sm tabular-nums text-n-slate-12">
        {{ timeText }}
      </span>
      <div ref="liveWave" class="flex-1 min-w-0" />
    </div>

    <div
      v-show="state === PAUSED"
      class="flex items-center flex-1 min-w-0 gap-2"
    >
      <NextButton
        v-tooltip.top="
          isPlaying
            ? $t('OUTSIDER_WHATSAPP.COMPOSER.STOP_PLAY')
            : $t('OUTSIDER_WHATSAPP.COMPOSER.PLAY')
        "
        :icon="isPlaying ? 'i-ph-pause-fill' : 'i-ph-play-fill'"
        slate
        ghost
        class="!rounded-full flex-shrink-0 [&>span]:size-5"
        @click="togglePlay"
      />
      <div ref="previewWave" class="flex-1 min-w-0 cursor-pointer" />
      <span class="flex-shrink-0 w-12 text-sm tabular-nums text-n-slate-11">
        {{ timeText }}
      </span>
    </div>

    <NextButton
      v-if="state === RECORDING"
      v-tooltip.top="$t('OUTSIDER_WHATSAPP.COMPOSER.PAUSE')"
      icon="i-ph-pause-fill"
      ruby
      faded
      class="!rounded-full flex-shrink-0 [&>span]:size-5"
      @click="pause"
    />
    <NextButton
      v-else-if="state === PAUSED"
      v-tooltip.top="$t('OUTSIDER_WHATSAPP.COMPOSER.RESUME')"
      icon="i-ph-microphone-fill"
      ruby
      faded
      class="!rounded-full flex-shrink-0 [&>span]:size-5"
      @click="resume"
    />
    <NextButton
      v-tooltip.top="$t('OUTSIDER_WHATSAPP.COMPOSER.SEND')"
      icon="i-ph-paper-plane-right-fill"
      :is-loading="state === SENDING"
      :disabled="state === SENDING"
      class="!rounded-full flex-shrink-0 !bg-[#00a884] !text-white hover:enabled:!bg-[#008f6f] [&>span]:size-5"
      @click="send"
    />
  </div>
</template>
