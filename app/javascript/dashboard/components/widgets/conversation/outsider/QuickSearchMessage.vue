<script setup>
// OUTSIDER: uma mensagem achada pela busca da lista de conversas: contato, data, quem mandou e o
// trecho com as palavras buscadas em destaque. Clicar abre a conversa nessa mensagem.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { timeAgo } from 'dashboard/helper/outsider/timeAgo';
import { highlightParts } from 'dashboard/composables/outsider/useQuickSearch';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  message: { type: Object, required: true },
  terms: { type: Array, default: () => [] },
  active: { type: Boolean, default: false },
});

const emit = defineEmits(['open']);

const { t, locale } = useI18n();
const getInbox = useMapGetter('inboxes/getInbox');
const inboxes = useMapGetter('inboxes/getInboxes');

// message_type 1 = enviada pela equipe
const isOutgoing = computed(() => props.message.message_type === 1);

const senderLabel = computed(() => {
  if (props.message.private) return t('OUTSIDER_TOOLS.SEARCH.PRIVATE_NOTE');
  if (isOutgoing.value) return props.message.sender_name || '';
  return '';
});

const inboxName = computed(() =>
  inboxes.value.length > 1
    ? getInbox.value(props.message.conversation.inbox_id)?.name
    : ''
);

const parts = computed(() =>
  highlightParts(props.message.content, props.terms)
);
</script>

<template>
  <button
    type="button"
    class="flex w-full gap-3 px-3 py-2.5 text-start rounded-lg hover:bg-n-alpha-2"
    :class="{ 'bg-n-alpha-2': active }"
    @click="emit('open', message)"
  >
    <Avatar
      :name="message.contact.name || ''"
      :src="message.contact.thumbnail"
      :size="32"
      rounded-full
    />
    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ message.contact.name }}
        </span>
        <span class="text-xs shrink-0 text-n-slate-10">
          {{ timeAgo(message.created_at, locale) }}
        </span>
      </div>
      <p class="text-xs leading-5 text-n-slate-11 line-clamp-2 break-words">
        <Icon
          v-if="message.attachment_type"
          icon="i-lucide-paperclip"
          class="inline-block size-3 ltr:mr-0.5 rtl:ml-0.5 align-[-2px]"
        />
        <span
          v-if="senderLabel"
          class="font-medium"
          :class="message.private ? 'text-n-amber-11' : 'text-n-slate-12'"
        >
          {{ senderLabel }}:
        </span>
        <template v-for="(part, index) in parts" :key="index">
          <mark
            v-if="part.match"
            class="px-0.5 font-medium rounded-sm bg-n-amber-4 text-n-slate-12"
          >
            {{ part.text }}
          </mark>
          <template v-else>{{ part.text }}</template>
        </template>
      </p>
      <span v-if="inboxName" class="text-[11px] truncate text-n-slate-10">
        {{ inboxName }}
      </span>
    </div>
  </button>
</template>
