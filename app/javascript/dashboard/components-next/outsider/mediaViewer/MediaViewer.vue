<script setup>
// OUTSIDER: visualizador de fotos, vídeos e áudios no estilo WhatsApp. Entra no lugar do
// GalleryView.vue do Chatwoot pelo apelido (alias) no vite.shared.ts, com as mesmas propriedades,
// então todo lugar que abria a galeria (balões, álbum, arquivos do contato) abre este.
// Mostra quem mandou e quando, a posição ("3 de 12"), a fila de miniaturas embaixo (a atual em
// destaque), ir até a mensagem, encaminhar, baixar, zoom e girar. Setas do teclado e Esc.
import { ref, computed, watch, nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useImageZoom } from 'dashboard/composables/useImageZoom';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { downloadFile } from '@chatwoot/utils';
import { jumpToMessage } from 'dashboard/composables/outsider/useConversationHistory';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import Avatar from 'next/avatar/Avatar.vue';
import { byOldest, fileNameOf, isViewable } from './mediaHelpers';

const props = defineProps({
  attachment: { type: Object, required: true },
  allAttachments: { type: Array, required: true },
  autoPlay: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);
const show = defineModel('show', { type: Boolean, default: false });

const { t } = useI18n();
const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');
const currentChat = useMapGetter('getSelectedChat');
const accountId = useMapGetter('getCurrentAccountId');

const items = computed(() => {
  const list = props.allAttachments.filter(isViewable);
  if (!list.some(item => item.id === props.attachment.id) && isViewable(props.attachment)) {
    list.push(props.attachment);
  }
  return list.sort(byOldest);
});

// o Chatwoot achava a posição pelo id da mensagem (num álbum todas têm o mesmo) e, sem achar,
// mostrava "0 / 97"; aqui é pelo id do anexo, depois pelo endereço e só então pela mensagem
const findStart = () => {
  const { id, data_url: url, message_id: messageId } = props.attachment;
  const tries = [
    item => id && item.id === id,
    item => url && item.data_url === url,
    item => messageId && item.message_id === messageId,
  ];
  const found = tries
    .map(test => items.value.findIndex(test))
    .find(index => index >= 0);
  return found ?? 0;
};

const index = ref(findStart());
const active = computed(() => items.value[index.value] || props.attachment);
const type = computed(() => active.value.file_type);
const isImage = computed(() => type.value === 'image');
const isVideo = computed(() => ['video', 'ig_reel'].includes(type.value));
const isAudio = computed(() => type.value === 'audio');
const total = computed(() => items.value.length);

const imageRef = useTemplateRef('imageRef');
const {
  imageWrapperStyle,
  imageStyle,
  onRotate,
  activeImageRotation,
  onZoom,
  onDoubleClickZoomImage,
  onWheelImageZoom,
  onMouseMove,
  onMouseLeave,
  resetZoomAndRotation,
} = useImageZoom(imageRef);

const sender = computed(() => {
  const data = active.value.sender || {};
  const isMe = data.type === 'user' && data.id === currentUser.value?.id;
  return {
    name: isMe ? t('OUTSIDER_WHATSAPP.LOOK.YOU') : data.name || data.available_name || '',
    avatar: data.thumbnail || data.avatar_url || '',
  };
});

const when = computed(() => {
  const createdAt = active.value.created_at;
  if (!createdAt) return '';
  return t('OUTSIDER_WHATSAPP.VIEWER.WHEN', {
    date: messageTimestamp(createdAt, 'dd/MM/yyyy'),
    time: messageTimestamp(createdAt, 'HH:mm'),
  });
});

const fileName = computed(() => fileNameOf(active.value));

const close = () => {
  show.value = false;
  emit('close');
};

const go = target => {
  if (target < 0 || target >= total.value || target === index.value) return;
  index.value = target;
  resetZoomAndRotation();
};

const stripRef = ref(null);
watch(
  index,
  async current => {
    await nextTick();
    stripRef.value
      ?.querySelectorAll('[data-thumb]')
      [current]?.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' });
  },
  { immediate: true }
);

const isDownloading = ref(false);
const download = async () => {
  const { file_type: fileType, data_url: url, extension } = active.value;
  try {
    isDownloading.value = true;
    await downloadFile({ url, type: fileType, extension });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};

// encaminhar sai pela caixa da conversa aberta (como o encaminhar da mensagem)
const canForward = computed(() => !!currentChat.value?.id && !!active.value.id);
const forward = () => {
  emitter.emit('CMD_OPEN_CUSTOM_FORWARD', {
    content: '',
    attachments: [{ id: active.value.id }],
    inboxId: currentChat.value.inbox_id,
  });
};

const canJump = computed(() => !!active.value.message_id);
const goToMessage = () => {
  const { message_id: messageId, conversation_id: conversationId } = active.value;
  close();
  const chatId = currentChat.value?.id;
  if (!conversationId || conversationId === chatId) {
    if (chatId) jumpToMessage(messageId);
    return;
  }
  router.push({
    name: 'inbox_conversation',
    params: { accountId: accountId.value, conversation_id: conversationId },
    query: { messageId },
  });
};

useKeyboardEvents({
  Escape: { action: close },
  ArrowLeft: { action: () => go(index.value - 1) },
  ArrowRight: { action: () => go(index.value + 1) },
});

const thumbOf = item => item.thumb_url || item.data_url;
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-[9999] flex flex-col text-white select-none"
      style="background: #0b141a"
      data-media-viewer
      @click.self="close"
    >
      <header class="flex items-center gap-3 px-4 h-16 shrink-0">
        <Avatar
          :name="sender.name || '?'"
          :src="sender.avatar"
          :size="40"
          rounded-full
        />
        <div class="flex flex-col min-w-0 shrink-0 max-w-[30%]">
          <span class="text-[15px] font-medium truncate">{{ sender.name }}</span>
          <span class="text-xs text-white/60">{{ when }}</span>
        </div>
        <span
          class="flex-1 min-w-0 px-4 text-sm text-center truncate text-white/70"
          :title="fileName"
        >
          {{ fileName }}
        </span>
        <div class="flex items-center gap-1 shrink-0">
          <template v-if="isImage">
            <button
              v-tooltip.bottom="t('OUTSIDER_WHATSAPP.VIEWER.ZOOM_OUT')"
              type="button"
              class="viewer-btn"
              @click="onZoom(-0.2)"
            >
              <span class="i-lucide-zoom-out size-5" />
            </button>
            <button
              v-tooltip.bottom="t('OUTSIDER_WHATSAPP.VIEWER.ZOOM_IN')"
              type="button"
              class="viewer-btn"
              @click="onZoom(0.2)"
            >
              <span class="i-lucide-zoom-in size-5" />
            </button>
            <button
              v-tooltip.bottom="t('OUTSIDER_WHATSAPP.VIEWER.ROTATE')"
              type="button"
              class="viewer-btn"
              @click="onRotate('clockwise')"
            >
              <span class="i-lucide-rotate-cw size-5" />
            </button>
          </template>
          <button
            v-if="canJump"
            v-tooltip.bottom="t('OUTSIDER_WHATSAPP.VIEWER.GO_TO_MESSAGE')"
            type="button"
            class="viewer-btn"
            data-viewer-jump
            @click="goToMessage"
          >
            <span class="i-lucide-message-square-text size-5" />
          </button>
          <button
            v-if="canForward"
            v-tooltip.bottom="t('OUTSIDER_WHATSAPP.FORWARD.BUTTON')"
            type="button"
            class="viewer-btn"
            @click="forward"
          >
            <span class="i-lucide-forward size-5" />
          </button>
          <button
            v-tooltip.bottom="t('OUTSIDER_WHATSAPP.VIEWER.DOWNLOAD')"
            type="button"
            class="viewer-btn"
            :disabled="isDownloading"
            @click="download"
          >
            <span
              :class="isDownloading ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-download'"
              class="size-5"
            />
          </button>
          <span class="w-px h-6 mx-1 bg-white/20" />
          <button
            v-tooltip.bottom="t('OUTSIDER_WHATSAPP.VIEWER.CLOSE')"
            type="button"
            class="viewer-btn"
            data-viewer-close
            @click="close"
          >
            <span class="i-lucide-x size-6" />
          </button>
        </div>
      </header>

      <main class="relative flex items-center flex-1 min-h-0" @click.self="close">
        <button
          v-if="total > 1"
          type="button"
          class="viewer-nav ltr:left-4 rtl:right-4"
          :disabled="index === 0"
          @click.stop="go(index - 1)"
        >
          <span class="ltr:i-lucide-chevron-left rtl:i-lucide-chevron-right size-6" />
        </button>

        <div
          class="flex items-center justify-center flex-1 h-full min-w-0 px-20 py-2 overflow-hidden"
          @click.self="close"
        >
          <div
            v-if="isImage"
            :style="imageWrapperStyle"
            class="flex items-center justify-center origin-center"
            :class="
              activeImageRotation % 180 !== 0
                ? 'w-[calc(100dvh-14rem)] h-[calc(100dvw-10rem)]'
                : 'size-full'
            "
            @click.self="close"
          >
            <img
              ref="imageRef"
              :key="active.id || active.data_url"
              :src="active.data_url"
              :style="imageStyle"
              class="object-contain max-w-full max-h-full duration-100 ease-in-out shadow-2xl select-none"
              @dblclick.stop="onDoubleClickZoomImage"
              @wheel.prevent.stop="onWheelImageZoom"
              @mousemove="onMouseMove"
              @mouseleave="onMouseLeave"
            />
          </div>
          <video
            v-else-if="isVideo"
            :key="active.id || active.data_url"
            :src="active.data_url"
            controls
            playsinline
            :autoplay="autoPlay"
            class="max-w-full max-h-full"
          />
          <div
            v-else-if="isAudio"
            class="flex flex-col items-center w-full max-w-md gap-6"
          >
            <span
              class="grid rounded-full size-32 place-items-center bg-[#F59E0B]"
            >
              <span class="i-lucide-headphones size-14" />
            </span>
            <audio
              :key="active.id || active.data_url"
              controls
              :autoplay="autoPlay"
              class="w-full"
              :src="active.data_url"
            />
          </div>
        </div>

        <button
          v-if="total > 1"
          type="button"
          class="viewer-nav ltr:right-4 rtl:left-4"
          :disabled="index === total - 1"
          @click.stop="go(index + 1)"
        >
          <span class="ltr:i-lucide-chevron-right rtl:i-lucide-chevron-left size-6" />
        </button>

        <span
          v-if="total > 1"
          class="absolute px-3 py-1 text-xs font-medium -translate-x-1/2 rounded-full pointer-events-none bottom-3 left-1/2 bg-black/50 tabular-nums"
          data-viewer-position
        >
          {{ t('OUTSIDER_WHATSAPP.VIEWER.POSITION', { current: index + 1, total }) }}
        </span>
      </main>

      <footer
        v-if="total > 1"
        class="border-t shrink-0 border-white/10 bg-black/20"
      >
        <div
          ref="stripRef"
          class="flex gap-2 px-4 py-3 overflow-x-auto [scrollbar-width:thin] [scrollbar-color:rgb(255_255_255/0.25)_transparent]"
        >
          <button
            v-for="(item, position) in items"
            :key="item.id || item.data_url"
            type="button"
            data-thumb
            class="relative !p-0 overflow-hidden rounded-md shrink-0 size-[72px] bg-white/5 transition-all outline outline-2 -outline-offset-2"
            :class="
              position === index
                ? 'outline-[#25D366] opacity-100'
                : 'outline-transparent opacity-60 hover:opacity-100'
            "
            @click="go(position)"
          >
            <img
              v-if="item.file_type === 'image'"
              :src="thumbOf(item)"
              loading="lazy"
              class="object-cover size-full"
            />
            <template v-else-if="['video', 'ig_reel'].includes(item.file_type)">
              <video
                :src="item.data_url"
                preload="metadata"
                muted
                class="object-cover size-full pointer-events-none"
              />
              <span class="absolute inset-0 grid place-items-center">
                <span class="grid rounded-full size-7 place-items-center bg-black/50">
                  <span class="i-lucide-play size-4" />
                </span>
              </span>
            </template>
            <span
              v-else
              class="grid size-full place-items-center bg-[#F59E0B]"
            >
              <span class="i-lucide-headphones size-6" />
            </span>
          </button>
        </div>
      </footer>
    </div>
  </TeleportWithDirection>
</template>

<style scoped>
.viewer-btn {
  @apply grid size-10 place-items-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white disabled:opacity-40;
}

.viewer-nav {
  @apply absolute z-10 grid size-12 place-items-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20 disabled:opacity-0 top-1/2 -translate-y-1/2;
}
</style>
