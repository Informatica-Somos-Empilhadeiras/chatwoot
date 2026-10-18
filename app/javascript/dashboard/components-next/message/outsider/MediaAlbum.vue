<script setup>
// OUTSIDER: bolha de álbum estilo WhatsApp (ver helper/outsider/mediaAlbum.js).
// Mostra as 4 primeiras mídias em grade 2x2 e "+N" na última; clicar abre a
// galeria do Chatwoot já posicionada naquela mídia.
import { ref, computed } from 'vue';
import BaseBubble from '../bubbles/Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import { ATTACHMENT_TYPES } from '../constants';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const VISIBLE_ITEMS = 4;

const { filteredCurrentChatAttachments, attachments } = useMessageContext();

const selectedAttachment = ref(null);
const failedIds = ref([]);

const visibleAttachments = computed(() =>
  attachments.value.slice(0, VISIBLE_ITEMS)
);
const hiddenCount = computed(() => attachments.value.length - VISIBLE_ITEMS);

const isVideo = attachment => attachment.fileType === ATTACHMENT_TYPES.VIDEO;
</script>

<template>
  <BaseBubble class="p-1" data-bubble-name="media-album">
    <div class="grid grid-cols-2 gap-1 w-64 max-w-full">
      <button
        v-for="(attachment, index) in visibleAttachments"
        :key="attachment.id"
        type="button"
        class="relative aspect-square overflow-hidden rounded-lg bg-n-alpha-2"
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
          class="size-full object-cover skip-context-menu"
          muted
          playsinline
          preload="metadata"
          @error="failedIds.push(attachment.id)"
        />
        <img
          v-else
          :src="attachment.thumbUrl || attachment.dataUrl"
          class="size-full object-cover skip-context-menu"
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
