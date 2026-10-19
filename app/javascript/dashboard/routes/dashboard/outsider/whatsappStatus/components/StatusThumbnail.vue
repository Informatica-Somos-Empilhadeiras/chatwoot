<script setup>
// OUTSIDER: miniatura de um status (texto colorido, foto ou vídeo).
import { ref, computed } from 'vue';
import { useIntersectionObserver } from '@vueuse/core';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { colorFor, durationLabel, fetchMedia } from '../helpers';

const props = defineProps({
  status: { type: Object, required: true },
  large: { type: Boolean, default: false },
  // na grade dos contatos o nome fica no rodapé, no lugar da duração do vídeo
  hideDuration: { type: Boolean, default: false },
  // com a caixa, a foto inteira é baixada quando aparece na tela (a miniatura do WhatsApp é pequena)
  inboxId: { type: Number, default: null },
});

const root = ref(null);
const mediaUrl = ref('');

const image = computed(() => mediaUrl.value || props.status.thumbnail);

if (props.inboxId && props.status.type === 'image' && !props.status.deleted) {
  const { stop } = useIntersectionObserver(root, ([entry]) => {
    if (!entry?.isIntersecting) return;
    stop();
    fetchMedia(props.inboxId, props.status.id, { preview: true })
      .then(({ url }) => {
        mediaUrl.value = url;
      })
      .catch(() => {});
  });
}
</script>

<template>
  <div
    ref="root"
    class="relative flex items-center justify-center overflow-hidden bg-n-alpha-2"
  >
    <div
      v-if="status.type === 'text'"
      class="flex items-center justify-center p-2 size-full"
      :style="{ backgroundColor: colorFor(status.id) }"
    >
      <span
        v-if="large"
        class="text-sm text-center text-white break-words whitespace-pre-line line-clamp-6"
      >
        {{ status.text }}
      </span>
      <Icon v-else icon="i-lucide-type" class="text-white size-5" />
    </div>
    <img v-else-if="image" :src="image" class="object-cover size-full" />
    <Icon
      v-else
      :icon="status.type === 'audio' ? 'i-lucide-mic' : 'i-lucide-image'"
      class="size-5 text-n-slate-10"
    />
    <div
      v-if="status.type === 'video'"
      class="absolute inset-0 flex items-center justify-center bg-n-black/20"
    >
      <span
        class="flex items-center justify-center text-white rounded-full bg-n-black/50"
        :class="large ? 'size-10' : 'size-6'"
      >
        <Icon icon="i-lucide-play" :class="large ? 'size-5' : 'size-3'" />
      </span>
      <span
        v-if="large && !hideDuration && status.seconds"
        class="absolute px-1.5 py-0.5 text-xs text-white rounded bottom-2 ltr:right-2 rtl:left-2 bg-n-black/50"
      >
        {{ durationLabel(status.seconds) }}
      </span>
    </div>
  </div>
</template>
