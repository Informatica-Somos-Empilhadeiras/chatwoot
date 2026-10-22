<script setup>
// OUTSIDER: player de áudio estilo WhatsApp (ver helper/outsider/voiceNote.js).
// Foto de quem enviou com o microfone (verde: ainda não ouvido neste navegador; azul: ouvido),
// play/pausa, onda do áudio que vai sendo pintada (clique ou arraste para pular), tempo e o botão
// de velocidade 1×/1,5×/2×, que fica no lugar da foto depois que o áudio começa, como no WhatsApp.
// Recebido: foto à esquerda; enviado: à direita. Baixar e a transcrição continuam aqui.
import {
  computed,
  getCurrentInstance,
  onMounted,
  ref,
  useTemplateRef,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntersectionObserver } from '@vueuse/core';
import { downloadFile } from '@chatwoot/utils';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { ORIENTATION } from '../constants';
import {
  BAR_COUNT,
  SPEEDS,
  formatClock,
  loadWaveform,
  markPlayed,
  placeholderWaveform,
  saveSpeed,
  savedSpeed,
  wasPlayed,
} from 'dashboard/helper/outsider/voiceNote';

const props = defineProps({
  attachment: { type: Object, required: true },
  sender: { type: Object, default: null },
  orientation: { type: String, default: ORIENTATION.LEFT },
  header: { type: String, default: '' },
});

const { t } = useI18n();
const { uid } = getCurrentInstance();

const audio = useTemplateRef('audio');
const root = useTemplateRef('root');
const track = useTemplateRef('track');

const isPlaying = ref(false);
const started = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const speed = ref(savedSpeed());
const played = ref(wasPlayed(props.attachment.id));
const bars = ref(placeholderWaveform(props.attachment.id));
const showFullTranscript = ref(false);

const isOutgoing = computed(() => props.orientation === ORIENTATION.RIGHT);
const source = computed(() => timeStampAppendedURL(props.attachment.dataUrl));
const progress = computed(() =>
  duration.value ? Math.min(1, currentTime.value / duration.value) : 0
);
const clock = computed(() =>
  formatClock(started.value ? currentTime.value : duration.value)
);
const speedLabel = computed(() => `${String(speed.value).replace('.', ',')}×`);
// no grupo o cabeçalho é "+55 ... - Nome": a foto usa as iniciais do nome
const senderName = computed(
  () =>
    props.header.split(' - ').pop() ||
    props.sender?.availableName ||
    props.sender?.name ||
    t('OUTSIDER_WHATSAPP.VOICE.SOMEONE')
);
const senderPhoto = computed(() =>
  props.header ? '' : props.sender?.thumbnail || props.sender?.avatarUrl || ''
);
const micClass = computed(() => {
  if (isOutgoing.value) return 'bg-n-slate-9';
  return played.value ? 'bg-[#53bdeb]' : 'bg-[#25d366]';
});

const transcript = computed(() => props.attachment.transcribedText || '');
const TRANSCRIPT_PREVIEW = 200;
const shownTranscript = computed(() =>
  showFullTranscript.value || transcript.value.length <= TRANSCRIPT_PREVIEW
    ? transcript.value
    : `${transcript.value.slice(0, TRANSCRIPT_PREVIEW).trimEnd()}…`
);

// a onda só é lida quando o áudio aparece na tela
const { stop: stopObserving } = useIntersectionObserver(root, ([entry]) => {
  if (!entry?.isIntersecting) return;
  stopObserving();
  loadWaveform(props.attachment.dataUrl, BAR_COUNT).then(result => {
    if (!result) return;
    bars.value = result.bars;
    if (!duration.value && Number.isFinite(result.duration)) {
      duration.value = result.duration;
    }
  });
});

// áudio gravado no navegador (WebM/Opus) chega sem a duração: pular para o fim obriga o
// navegador a calcular, e depois voltamos ao começo
const resolveStreamingDuration = () => {
  const element = audio.value;
  if (!element) return;
  const onTimeUpdate = () => {
    element.removeEventListener('timeupdate', onTimeUpdate);
    element.currentTime = 0;
    if (Number.isFinite(element.duration)) duration.value = element.duration;
  };
  element.addEventListener('timeupdate', onTimeUpdate);
  try {
    element.currentTime = Number.MAX_SAFE_INTEGER;
  } catch {
    element.removeEventListener('timeupdate', onTimeUpdate);
  }
};

const onLoadedMetadata = () => {
  const value = audio.value?.duration;
  if (Number.isFinite(value)) duration.value = value;
  else resolveStreamingDuration();
};

onMounted(() => {
  const value = audio.value?.duration;
  if (Number.isFinite(value)) duration.value = value;
});

useEmitter('pause_playing_audio', playingId => {
  if (playingId !== uid && isPlaying.value) {
    audio.value?.pause();
    isPlaying.value = false;
  }
});

const play = async () => {
  emitter.emit('pause_playing_audio', uid);
  audio.value.playbackRate = speed.value;
  try {
    await audio.value.play();
    isPlaying.value = true;
    started.value = true;
    if (!played.value && !isOutgoing.value) {
      played.value = true;
      markPlayed(props.attachment.id);
    }
  } catch {
    isPlaying.value = false;
  }
};

const togglePlay = () => {
  if (isPlaying.value) {
    audio.value.pause();
    isPlaying.value = false;
    return;
  }
  play();
};

const onEnded = () => {
  isPlaying.value = false;
  started.value = false;
  currentTime.value = 0;
};

const onTimeUpdate = () => {
  currentTime.value = audio.value?.currentTime || 0;
};

const cycleSpeed = () => {
  const next = SPEEDS[(SPEEDS.indexOf(speed.value) + 1) % SPEEDS.length];
  speed.value = next;
  saveSpeed(next);
  if (audio.value) audio.value.playbackRate = next;
};

const seekTo = clientX => {
  const box = track.value?.getBoundingClientRect();
  if (!box || !duration.value) return;
  const ratio = Math.min(1, Math.max(0, (clientX - box.left) / box.width));
  audio.value.currentTime = ratio * duration.value;
  currentTime.value = audio.value.currentTime;
  started.value = true;
};

const startSeek = event => {
  if (event.button !== 0) return;
  event.preventDefault();
  seekTo(event.clientX);
  const onMove = moveEvent => seekTo(moveEvent.clientX);
  const onUp = () => {
    window.removeEventListener('pointermove', onMove);
    window.removeEventListener('pointerup', onUp);
  };
  window.addEventListener('pointermove', onMove);
  window.addEventListener('pointerup', onUp);
};

const onTrackKey = event => {
  if (!duration.value) return;
  const step = { ArrowLeft: -5, ArrowRight: 5 }[event.key];
  if (!step) return;
  event.preventDefault();
  audio.value.currentTime = Math.min(
    duration.value,
    Math.max(0, audio.value.currentTime + step)
  );
  currentTime.value = audio.value.currentTime;
  started.value = true;
};

const download = () => {
  const { fileType, dataUrl, extension } = props.attachment;
  downloadFile({ url: dataUrl, type: fileType, extension });
};

const barPlayed = index => (index + 0.5) / bars.value.length <= progress.value;
</script>

<template>
  <div ref="root" class="flex flex-col gap-1 w-72 max-w-full">
    <audio
      ref="audio"
      class="hidden"
      preload="metadata"
      playsinline
      @loadedmetadata="onLoadedMetadata"
      @timeupdate="onTimeUpdate"
      @ended="onEnded"
    >
      <source :src="source" />
    </audio>
    <p v-if="header" class="px-1 mb-0 font-semibold">{{ `${header}:` }}</p>
    <div
      class="flex items-center gap-2"
      :class="{ 'flex-row-reverse': isOutgoing }"
    >
      <!-- foto com microfone; depois que começa, a velocidade -->
      <div class="relative grid shrink-0 size-12 place-content-center">
        <button
          v-if="started"
          type="button"
          class="h-7 px-2.5 rounded-full text-xs font-semibold tabular-nums bg-n-alpha-3 text-n-slate-12 hover:bg-n-alpha-2"
          :title="t('OUTSIDER_WHATSAPP.VOICE.SPEED')"
          data-voice-speed
          @click="cycleSpeed"
        >
          {{ speedLabel }}
        </button>
        <template v-else>
          <Avatar
            :name="senderName"
            :src="senderPhoto"
            :size="48"
            rounded-full
          />
          <span
            class="absolute grid text-white rounded-full -bottom-0.5 size-5 place-content-center ring-2 ring-n-background"
            :class="[micClass, isOutgoing ? '-left-0.5' : '-right-0.5']"
          >
            <Icon icon="i-ph-microphone-fill" class="size-3" />
          </span>
        </template>
      </div>
      <div class="flex items-center flex-1 min-w-0 gap-2">
        <button
          type="button"
          class="grid shrink-0 size-8 place-content-center text-n-slate-11 hover:text-n-slate-12"
          :aria-label="
            isPlaying
              ? t('OUTSIDER_WHATSAPP.VOICE.PAUSE')
              : t('OUTSIDER_WHATSAPP.VOICE.PLAY')
          "
          data-voice-play
          @click="togglePlay"
        >
          <Icon
            :icon="isPlaying ? 'i-ph-pause-fill' : 'i-ph-play-fill'"
            class="size-7"
          />
        </button>
        <div class="flex flex-col flex-1 min-w-0 gap-0.5 pt-3">
          <div
            ref="track"
            class="relative flex items-center h-7 gap-[2px] cursor-pointer touch-none focus:outline-none"
            role="slider"
            tabindex="0"
            :aria-label="t('OUTSIDER_WHATSAPP.VOICE.POSITION')"
            aria-valuemin="0"
            :aria-valuemax="Math.round(duration)"
            :aria-valuenow="Math.round(currentTime)"
            data-voice-track
            @pointerdown="startSeek"
            @keydown="onTrackKey"
          >
            <span
              v-for="(height, index) in bars"
              :key="index"
              class="flex-1 min-w-[2px] rounded-full transition-colors"
              :class="barPlayed(index) ? 'bg-n-slate-11' : 'bg-n-slate-11/35'"
              :style="{ height: `${Math.round(height * 100)}%` }"
            />
            <span
              class="absolute rounded-full pointer-events-none size-3 -translate-x-1/2 shadow-sm"
              :class="isOutgoing ? 'bg-n-teal-10' : 'bg-[#53bdeb]'"
              :style="{ left: `${progress * 100}%` }"
            />
          </div>
          <div
            class="flex items-center justify-between text-xs text-n-slate-11"
          >
            <span class="tabular-nums" data-voice-clock>{{ clock }}</span>
            <button
              type="button"
              class="grid rounded-full size-5 place-content-center hover:text-n-slate-12"
              :title="t('OUTSIDER_WHATSAPP.VOICE.DOWNLOAD')"
              @click="download"
            >
              <Icon icon="i-lucide-download" class="size-3.5" />
            </button>
          </div>
        </div>
      </div>
    </div>
    <div
      v-if="transcript"
      class="p-2 mt-1 text-sm break-words rounded-lg bg-n-alpha-1 text-n-slate-12"
    >
      {{ shownTranscript }}
      <button
        v-if="transcript.length > TRANSCRIPT_PREVIEW"
        type="button"
        class="block p-0 mt-1 font-medium bg-transparent border-0 text-n-slate-11 hover:text-n-slate-12"
        @click="showFullTranscript = !showFullTranscript"
      >
        {{
          showFullTranscript
            ? $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_LESS')
            : $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_MORE')
        }}
      </button>
    </div>
  </div>
</template>
