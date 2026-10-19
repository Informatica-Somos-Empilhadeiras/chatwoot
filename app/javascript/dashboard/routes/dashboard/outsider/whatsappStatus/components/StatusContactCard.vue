<script setup>
// OUTSIDER: um contato na grade de status, com a prévia do primeiro status ainda não visto
// (ou do último, quando já viu todos) e uma barrinha por status, como no WhatsApp.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import StatusThumbnail from './StatusThumbnail.vue';
import { timeLabel } from '../helpers';

const props = defineProps({
  author: { type: Object, required: true },
  seen: { type: Object, default: () => ({}) },
  inboxId: { type: Number, required: true },
});

const { t } = useI18n();

const last = computed(() => props.author.statuses.at(-1));
const cover = computed(
  () =>
    props.author.statuses.find(status => !props.seen[status.id]) || last.value
);
const hasUnseen = computed(() =>
  props.author.statuses.some(status => !props.seen[status.id])
);
</script>

<template>
  <button
    type="button"
    class="relative block w-full p-0 overflow-hidden outline outline-1 -outline-offset-1 outline-n-container text-start rounded-xl aspect-[4/5] bg-n-solid-2 group"
  >
    <!-- a chave refaz a miniatura quando a prévia muda, para baixar a foto nova -->
    <StatusThumbnail
      :key="cover.id"
      :status="cover"
      :inbox-id="inboxId"
      large
      hide-duration
      class="absolute inset-0 transition-transform duration-300 size-full group-hover:scale-105"
    />
    <!-- com muitos status, as barrinhas ficam coladas para caber no cartão -->
    <div
      class="absolute flex inset-x-2 top-2"
      :class="author.statuses.length > 20 ? 'gap-px' : 'gap-1'"
    >
      <span
        v-for="status in author.statuses"
        :key="status.id"
        class="flex-1 h-1 rounded-full shadow"
        :class="seen[status.id] ? 'bg-white/40' : 'bg-white'"
      />
    </div>
    <div
      class="absolute inset-x-0 bottom-0 flex items-center gap-2 px-2 pt-10 pb-2 bg-gradient-to-t from-black/80 via-black/40 to-transparent"
    >
      <span
        class="flex flex-shrink-0 rounded-full ring-2"
        :class="hasUnseen ? 'ring-n-teal-9' : 'ring-white/40'"
      >
        <Avatar
          :name="author.name"
          :src="author.avatar_url"
          :size="28"
          rounded-full
        />
      </span>
      <span class="flex flex-col min-w-0">
        <span class="text-sm font-medium text-white truncate">
          {{ author.name }}
        </span>
        <span class="text-xs truncate text-white/80">
          {{ timeLabel(t, last.timestamp) }}
        </span>
      </span>
    </div>
  </button>
</template>
