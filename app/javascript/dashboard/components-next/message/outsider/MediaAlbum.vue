<script setup>
// OUTSIDER: bolha de álbum estilo WhatsApp (ver helper/outsider/mediaAlbum.js).
// 2 mídias: lado a lado; 3: uma larga em cima e duas embaixo; 4+: grade 2x2
// com "+N" na última. Em grupo, mostra quem enviou em cima e aceita 1 mídia só.
// Clicar abre a galeria do Chatwoot naquela mídia.
import { ref, computed } from 'vue';
import BaseBubble from '../bubbles/Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import { ATTACHMENT_TYPES } from '../constants';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const VISIBLE_ITEMS = 4;

const { filteredCurrentChatAttachments, attachments, content } =
  useMessageContext();

const senderHeader = computed(() => splitSenderHeader(content.value).header);

const selectedAttachment = ref(null);
const failedIds = ref([]);

const visibleAttachments = computed(() =>
  attachments.value.slice(0, VISIBLE_ITEMS)
);
const hiddenCount = computed(() => attachments.value.length - VISIBLE_ITEMS);

const isSingle = computed(() => attachments.value.length === 1);

const tileClass = index => {
  if (isSingle.value) return 'col-span-2 max-h-96';
  if (index === 0 && attachments.value.length === 3) {
    return 'col-span-2 aspect-[2/1]';
  }
  return 'aspect-square';
};

const mediaClass = computed(() =>
  isSingle.value ? 'w-full h-auto object-cover' : 'size-full object-cover'
);

const isVideo = attachment => attachment.fileType === ATTACHMENT_TYPES.VIDEO;
</script>

<template>
  <BaseBubble class="p-1" data-bubble-name="media-album">
    <p v-if="senderHeader" class="px-2 pt-1 pb-2 mb-0 font-semibold">
      {{ `${senderHeader}:` }}
    </p>
    <div class="grid grid-cols-2 gap-1 w-64 max-w-full">
      <button
        v-for="(attachment, index) in visibleAttachments"
        :key="attachment.id"
        type="button"
        class="relative overflow-hidden rounded-lg bg-n-alpha-2"
        :class="tileClass(index)"
        @click="selectedAttachment = attachment"
      >
        <Icon
          v-if="failedIds.includes(attachment.id)"
          icon="i-lucide-circle-off"
          class="absolute inset-0 m-auto text-n-slate-11"
        />
        <video
          v-else-if="isVideo(attachment)"
          :src="attachment.dataUrl"
          class="skip-context-menu"
          :class="mediaClass"
          muted
          playsinline
          preload="metadata"
          @error="failedIds.push(attachment.id)"
        />
        <img
          v-else
          :src="attachment.thumbUrl || attachment.dataUrl"
          class="skip-context-menu"
          :class="mediaClass"
          loading="lazy"
          @error="failedIds.push(attachment.id)"
        />
        <span
          v-if="isVideo(attachment)"
          class="absolute inset-0 m-auto size-9 flex items-center justify-center rounded-full bg-black/50 text-white"
        >
          <Icon icon="i-lucide-play" class="size-5" />
        </span>
        <span
          v-if="index === VISIBLE_ITEMS - 1 && hiddenCount > 0"
          class="absolute inset-0 flex items-center justify-center bg-black/50 text-3xl font-medium text-white"
        >
          {{ `+${hiddenCount}` }}
        </span>
      </button>
    </div>
  </BaseBubble>
  <GalleryView
    v-if="selectedAttachment"
    show
    :attachment="useSnakeCase(selectedAttachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @update:show="selectedAttachment = null"
    @close="selectedAttachment = null"
  />
</template>
