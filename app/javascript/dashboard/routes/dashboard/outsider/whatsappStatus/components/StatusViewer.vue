<script setup>
// OUTSIDER: visualizador de status em tela cheia, como no WhatsApp Web.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import StatusMedia from './StatusMedia.vue';
import { colorFor, fetchMedia, timeLabel } from '../helpers';

const props = defineProps({
  // uma pessoa por item: { name, avatar_url, contact_id, statuses }
  stories: { type: Array, required: true },
  startIndex: { type: Number, default: 0 },
  seen: { type: Object, default: () => ({}) },
  inboxId: { type: Number, required: true },
  isMine: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'seen', 'interactions']);

// tempo de cada status de texto ou foto; vídeo e áudio duram o que durarem
const TIMED_DURATION = 6000;
// limite por quadro, para não pular status quando a aba volta do segundo plano
const MAX_FRAME = 100;

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const firstUnseen = story =>
  Math.max(
    story.statuses.findIndex(status => !props.seen[status.id]),
    0
  );

const storyIndex = ref(props.startIndex);
const statusIndex = ref(firstUnseen(props.stories[props.startIndex]));
const progress = ref(0);
const ready = ref(false);
const mediaUrl = ref('');
const mediaFailed = ref(false);
const userPaused = ref(false);
const holding = ref(false);
const muted = ref(false);
const mediaRef = ref(null);

const story = computed(() => props.stories[storyIndex.value]);
const status = computed(() => story.value.statuses[statusIndex.value]);
const paused = computed(() => userPaused.value || holding.value);
const isPlayable = computed(
  () => ['video', 'audio'].includes(status.value.type) && !mediaFailed.value
);
const hasPrevious = computed(
  () => storyIndex.value > 0 || statusIndex.value > 0
);
const caption = computed(() =>
  status.value.type === 'text' ? '' : status.value.text
);
const background = computed(() =>
  status.value.type === 'text'
    ? { backgroundColor: colorFor(status.value.id) }
    : {}
);

let elapsed = 0;
let lastFrame = null;
let frame = null;

const close = () => {
  ready.value = false;
  emit('close');
};

const goTo = (nextStoryIndex, nextStatusIndex) => {
  storyIndex.value = nextStoryIndex;
  statusIndex.value = nextStatusIndex;
};

const next = () => {
  if (statusIndex.value < story.value.statuses.length - 1) {
    goTo(storyIndex.value, statusIndex.value + 1);
  } else if (storyIndex.value < props.stories.length - 1) {
    goTo(
      storyIndex.value + 1,
      firstUnseen(props.stories[storyIndex.value + 1])
    );
  } else {
    close();
  }
};

const previous = () => {
  if (statusIndex.value > 0) {
    goTo(storyIndex.value, statusIndex.value - 1);
  } else if (storyIndex.value > 0) {
    const previousStory = props.stories[storyIndex.value - 1];
    goTo(storyIndex.value - 1, previousStory.statuses.length - 1);
  }
};

const nextStatus = () => {
  if (statusIndex.value < story.value.statuses.length - 1) {
    return story.value.statuses[statusIndex.value + 1];
  }
  const nextStory = props.stories[storyIndex.value + 1];
  return nextStory?.statuses[firstUnseen(nextStory)];
};

const loadMedia = () => {
  const current = status.value;
  elapsed = 0;
  progress.value = 0;
  ready.value = false;
  mediaUrl.value = '';
  mediaFailed.value = false;
  if (!props.isMine) emit('seen', current.id);
  if (current.type === 'text') return;

  fetchMedia(props.inboxId, current.id)
    .then(({ url }) => {
      if (status.value.id === current.id) mediaUrl.value = url;
    })
    .catch(() => {
      if (status.value.id === current.id) mediaFailed.value = true;
    });

  const upcoming = nextStatus();
  if (upcoming && upcoming.type !== 'text') {
    fetchMedia(props.inboxId, upcoming.id).catch(() => {});
  }
};

watch(() => status.value.id, loadMedia, { immediate: true });

const tick = now => {
  const delta = lastFrame === null ? 0 : Math.min(now - lastFrame, MAX_FRAME);
  lastFrame = now;
  if (ready.value && !paused.value) {
    if (isPlayable.value) {
      progress.value = mediaRef.value?.playbackProgress() || 0;
    } else {
      elapsed += delta;
      progress.value = Math.min(elapsed / TIMED_DURATION, 1);
      if (elapsed >= TIMED_DURATION) next();
    }
  }
  frame = requestAnimationFrame(tick);
};

onMounted(() => {
  frame = requestAnimationFrame(tick);
});

onBeforeUnmount(() => {
  cancelAnimationFrame(frame);
});

const barWidth = index => {
  if (index < statusIndex.value) return 100;
  if (index > statusIndex.value) return 0;
  return progress.value * 100;
};

const openInteractions = () => {
  userPaused.value = true;
  emit('interactions', status.value);
};

useEventListener(document, 'keydown', event => {
  // com a janela de curtidas aberta por cima, as teclas são dela
  if (document.querySelector('dialog[open]')) return;
  if (event.key === 'Escape') close();
  else if (event.key === 'ArrowRight') next();
  else if (event.key === 'ArrowLeft') previous();
  else if (event.key === ' ') {
    event.preventDefault();
    userPaused.value = !userPaused.value;
  }
});
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      class="fixed inset-0 z-[9999] flex flex-col text-white bg-n-black select-none"
      :style="background"
    >
      <div class="flex flex-col w-full max-w-xl gap-3 px-4 pt-4 mx-auto">
        <div class="flex gap-1">
          <span
            v-for="(item, index) in story.statuses"
            :key="item.id"
            class="flex-1 h-0.5 overflow-hidden rounded-full bg-white/30"
          >
            <span
              class="block h-full bg-white"
              :style="{ width: `${barWidth(index)}%` }"
            />
          </span>
        </div>
        <div class="flex items-center gap-2">
          <Avatar
            :name="story.name"
            :src="story.avatar_url"
            :size="36"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0 ltr:ml-1 rtl:mr-1">
            <span class="text-sm font-medium truncate">{{ story.name }}</span>
            <span class="text-xs text-white/70">
              {{ timeLabel(t, status.timestamp) }}
            </span>
          </div>
          <router-link
            v-if="story.contact_id"
            :to="
              accountScopedRoute('contacts_edit', {
                contactId: story.contact_id,
              })
            "
            :title="t('OUTSIDER_WHATSAPP_STATUS.VIEWER.OPEN_CONTACT')"
            class="flex items-center justify-center rounded-full size-9 hover:bg-white/10"
          >
            <Icon icon="i-lucide-contact" class="size-5" />
          </router-link>
          <button
            v-if="isPlayable"
            type="button"
            :title="
              muted
                ? t('OUTSIDER_WHATSAPP_STATUS.VIEWER.UNMUTE')
                : t('OUTSIDER_WHATSAPP_STATUS.VIEWER.MUTE')
            "
            class="flex items-center justify-center rounded-full size-9 hover:bg-white/10"
            @click="muted = !muted"
          >
            <Icon
              :icon="muted ? 'i-lucide-volume-x' : 'i-lucide-volume-2'"
              class="size-5"
            />
          </button>
          <button
            type="button"
            :title="
              userPaused
                ? t('OUTSIDER_WHATSAPP_STATUS.VIEWER.PLAY')
                : t('OUTSIDER_WHATSAPP_STATUS.VIEWER.PAUSE')
            "
            class="flex items-center justify-center rounded-full size-9 hover:bg-white/10"
            @click="userPaused = !userPaused"
          >
            <Icon
              :icon="userPaused ? 'i-lucide-play' : 'i-lucide-pause'"
              class="size-5"
            />
          </button>
          <button
            type="button"
            :title="t('OUTSIDER_WHATSAPP_STATUS.VIEWER.CLOSE')"
            class="flex items-center justify-center rounded-full size-9 hover:bg-white/10"
            @click="close"
          >
            <Icon icon="i-lucide-x" class="size-6" />
          </button>
        </div>
      </div>

      <div
        class="relative flex items-center justify-center flex-1 min-h-0 py-4"
      >
        <button
          v-if="hasPrevious"
          type="button"
          :title="t('OUTSIDER_WHATSAPP_STATUS.VIEWER.PREVIOUS')"
          class="absolute z-10 flex items-center justify-center rounded-full size-11 ltr:left-4 rtl:right-4 bg-white/10 hover:bg-white/20"
          @click="previous"
        >
          <Icon icon="i-lucide-chevron-left" class="size-6 rtl:rotate-180" />
        </button>
        <div
          class="w-full h-full max-w-xl px-4"
          @pointerdown="holding = true"
          @pointerup="holding = false"
          @pointerleave="holding = false"
        >
          <StatusMedia
            ref="mediaRef"
            :key="status.id"
            v-model:muted="muted"
            :status="status"
            :media-url="mediaUrl"
            :failed="mediaFailed"
            :paused="paused"
            @ready="ready = true"
            @ended="next"
            @failed="mediaFailed = true"
          />
        </div>
        <button
          type="button"
          :title="t('OUTSIDER_WHATSAPP_STATUS.VIEWER.NEXT')"
          class="absolute z-10 flex items-center justify-center rounded-full size-11 ltr:right-4 rtl:left-4 bg-white/10 hover:bg-white/20"
          @click="next"
        >
          <Icon icon="i-lucide-chevron-right" class="size-6 rtl:rotate-180" />
        </button>
      </div>

      <div
        v-if="caption || isMine"
        class="flex flex-col items-center w-full max-w-xl gap-3 px-4 pb-6 mx-auto"
      >
        <p
          v-if="caption"
          class="text-sm text-center whitespace-pre-line line-clamp-4"
        >
          {{ caption }}
        </p>
        <button
          v-if="isMine"
          type="button"
          :title="t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.TITLE')"
          class="flex items-center gap-4 px-4 py-2 text-sm rounded-full bg-white/10 hover:bg-white/20"
          @click="openInteractions"
        >
          <span v-if="status.views != null" class="flex items-center gap-1.5">
            <Icon icon="i-lucide-eye" class="size-4" />
            {{ status.views }}
          </span>
          <span class="flex items-center gap-1.5">
            <Icon icon="i-lucide-heart" class="size-4" />
            {{ status.reactions.length }}
          </span>
          <span class="flex items-center gap-1.5">
            <Icon icon="i-lucide-message-circle-reply" class="size-4" />
            {{ status.replies.length }}
          </span>
        </button>
      </div>
    </div>
  </TeleportWithDirection>
</template>
