<script setup>
// OUTSIDER: conteúdo de um status dentro do visualizador.
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  status: { type: Object, required: true },
  mediaUrl: { type: String, default: '' },
  failed: { type: Boolean, default: false },
  paused: { type: Boolean, default: false },
});

const emit = defineEmits(['ready', 'ended', 'failed']);

const muted = defineModel('muted', { type: Boolean, default: false });

const { t } = useI18n();

const player = ref(null);

const textClass = computed(() => {
  const length = props.status.text?.length || 0;
  if (length < 60) return 'text-4xl';
  if (length < 200) return 'text-2xl';
  return 'text-lg';
});

// o texto já está pronto; foto e vídeo ficam prontos quando a mídia carrega ou falha
watch(
  () => [props.status.id, props.failed],
  () => {
    if (props.status.type === 'text' || props.failed) emit('ready');
  },
  { immediate: true }
);

const play = () => {
  player.value?.play().catch(() => {
    // o navegador não deixou tocar com som: toca sem som
    muted.value = true;
    nextTick(() => player.value?.play().catch(() => {}));
  });
};

watch(
  () => props.paused,
  paused => {
    if (!player.value) return;
    if (paused) player.value.pause();
    else play();
  }
);

const onLoaded = () => {
  emit('ready');
  if (!props.paused) play();
};

defineExpose({
  playbackProgress: () =>
    player.value?.duration
      ? player.value.currentTime / player.value.duration
      : 0,
});
</script>

<template>
  <div class="relative flex items-center justify-center w-full h-full">
    <p
      v-if="status.type === 'text'"
      class="px-8 font-medium leading-snug text-center text-white break-words whitespace-pre-line"
      :class="textClass"
    >
      {{ status.text }}
    </p>
    <template v-else-if="failed || !mediaUrl">
      <img
        v-if="status.thumbnail"
        :src="status.thumbnail"
        class="absolute inset-0 object-contain size-full blur-md opacity-60"
      />
      <p v-if="failed" class="relative px-4 text-sm text-center text-white">
        {{ t('OUTSIDER_WHATSAPP_STATUS.VIEWER.MEDIA_ERROR') }}
      </p>
      <Spinner v-else class="relative text-white" />
    </template>
    <img
      v-else-if="status.type === 'image'"
      :src="mediaUrl"
      class="object-contain max-w-full max-h-full"
      @load="emit('ready')"
      @error="emit('failed')"
    />
    <video
      v-else-if="status.type === 'video'"
      ref="player"
      :src="mediaUrl"
      :muted="muted"
      playsinline
      class="max-w-full max-h-full"
      @loadeddata="onLoaded"
      @ended="emit('ended')"
      @error="emit('failed')"
    />
    <div v-else class="flex flex-col items-center gap-4 text-white">
      <span
        class="flex items-center justify-center rounded-full size-24 bg-white/10"
      >
        <Icon icon="i-lucide-mic" class="size-10" />
      </span>
      <audio
        ref="player"
        :src="mediaUrl"
        :muted="muted"
        @loadeddata="onLoaded"
        @ended="emit('ended')"
        @error="emit('failed')"
      />
    </div>
  </div>
</template>
