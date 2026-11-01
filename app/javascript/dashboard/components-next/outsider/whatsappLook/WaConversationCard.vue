<script setup>
// OUTSIDER: card da lista de conversas no estilo WhatsApp/Telegram. Entra no lugar do
// ConversationCard.vue do Chatwoot (troca de import no ConversationItem.vue) com as mesmas
// propriedades e eventos, então menu de contexto, seleção em massa e abrir em outra aba seguem
// iguais. Foto grande com o selo do canal, nome e hora na primeira linha, ✓✓ + prévia + não
// lidas/fixada na segunda e, embaixo, quem está com a conversa, caixa, etiquetas e valor do CRM.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { useConversationPins } from 'dashboard/composables/outsider/useConversationPins';
import { chatListTime } from 'dashboard/helper/outsider/chatTime';
import { useMinuteClock } from './useMinuteClock';
import Avatar from 'next/avatar/Avatar.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import SLACardLabel from 'dashboard/components/widgets/conversation/components/SLACardLabel.vue';
import CrmValueChip from 'dashboard/routes/dashboard/outsider/crm/conversation/CrmValueChip.vue';
import ChannelAvatar from './ChannelAvatar.vue';
import ChatPreview from './ChatPreview.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const { t, locale } = useI18n();
const { isPinned } = useConversationPins();
const now = useMinuteClock();
const currentUserId = useMapGetter('getCurrentUserID');
const typingUsers = useMapGetter('conversationTypingStatus/getUserList');
const allLabels = useMapGetter('labels/getLabels');

const hovered = ref(false);

const contact = computed(() => ({
  ...(props.chat.meta?.sender || {}),
  ...props.currentContact,
}));
const isGroup = computed(() =>
  String(contact.value.identifier || '').endsWith('@g.us')
);
const unreadCount = computed(() => props.chat.unread_count || 0);
const hasUnread = computed(() => unreadCount.value > 0);
const lastMessage = computed(() => getLastMessage(props.chat));
const pinned = computed(() => isPinned(props.chat.id));

const time = computed(() =>
  chatListTime(props.chat.timestamp || props.chat.created_at, {
    locale: locale.value,
    yesterday: t('OUTSIDER_WHATSAPP.LOOK.YESTERDAY'),
    now: now.value,
  })
);

const typingName = computed(() => {
  const [first] = typingUsers.value(props.chat.id) || [];
  return first ? first.name || first.available_name || ' ' : '';
});

// quem está com a conversa: o agente (ou o bot), "Você" ou "Sem responsável"
const owner = computed(() => {
  const { assignee } = props;
  const isBot = props.chat.meta?.assignee_type === 'AgentBot';
  if (assignee?.id) {
    const isMe = !isBot && assignee.id === currentUserId.value;
    if (isMe && !props.showAssignee) return null;
    return {
      kind: isBot ? 'bot' : isMe ? 'me' : 'agent',
      name: isMe ? t('OUTSIDER_WHATSAPP.LOOK.YOU') : assignee.name,
      thumbnail: assignee.thumbnail || assignee.avatar_url || '',
    };
  }
  if (props.showAssignee && props.chat.status === 'open') {
    return { kind: 'none', name: t('OUTSIDER_WHATSAPP.LOOK.NO_OWNER') };
  }
  return null;
});

const labels = computed(() => {
  const titles = props.chat.labels || [];
  return titles.map(title => {
    const label = allLabels.value.find(item => item.title === title);
    return { title, color: label?.color || '#94A3B8' };
  });
});
const shownLabels = computed(() => labels.value.slice(0, 2));

const hasSla = computed(
  () => props.chat?.applied_sla?.id && !props.currentContact?.blocked
);

const selectedModel = computed({
  get: () => props.selected,
  set: checked =>
    emit(
      checked ? 'selectConversation' : 'deSelectConversation',
      props.chat.id,
      props.inbox.id
    ),
});

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);
</script>

<template>
  <div
    class="outsider-wa-card relative flex items-center gap-3 mx-2 my-px px-2.5 py-2 rounded-xl cursor-pointer select-none transition-colors duration-100"
    :class="{
      'bg-n-alpha-2 dark:bg-n-alpha-3 active': isActiveChat,
      'bg-n-brand/10 selected': selected && !isActiveChat,
      'hover:bg-n-alpha-1 dark:hover:bg-n-alpha-2': !isActiveChat,
    }"
    :data-conversation-id="chat.id"
    @click="emit('click', $event)"
    @contextmenu="emit('contextmenu', $event)"
  >
    <div
      v-if="!hideThumbnail"
      class="relative shrink-0"
      @mouseenter="hovered = true"
      @mouseleave="hovered = false"
    >
      <ChannelAvatar
        :name="contact.name"
        :src="contact.thumbnail"
        :inbox="inbox"
        :size="compact ? 40 : 48"
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="absolute inset-0 z-10 flex items-center justify-center rounded-full cursor-pointer bg-n-alpha-black1 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </ChannelAvatar>
    </div>

    <div class="flex flex-col flex-1 min-w-0 gap-0.5">
      <div class="flex items-center min-w-0 gap-2">
        <span
          v-if="isGroup"
          class="i-lucide-users size-3.5 shrink-0 text-n-slate-10"
        />
        <h4
          class="flex-1 min-w-0 my-0 truncate text-[15px] leading-5 text-n-slate-12"
          :class="hasUnread ? 'font-semibold' : 'font-medium'"
        >
          {{ contact.name }}
        </h4>
        <span
          class="text-xs shrink-0 tabular-nums"
          :class="
            hasUnread
              ? 'text-[#1DAA61] dark:text-[#21C063] font-semibold'
              : 'text-n-slate-10'
          "
        >
          {{ time }}
        </span>
      </div>

      <div class="flex items-center min-w-0 gap-2">
        <ChatPreview
          :message="lastMessage"
          :typing-name="typingName"
          :is-group="isGroup"
          class="flex-1 text-sm leading-5"
          :class="hasUnread ? 'text-n-slate-12' : 'text-n-slate-11'"
        />
        <div class="flex items-center gap-1.5 shrink-0">
          <CardPriorityIcon :priority="chat.priority" class="!size-4" />
          <span
            v-if="pinned"
            v-tooltip.top="t('OUTSIDER_WHATSAPP.LOOK.PINNED')"
            class="i-lucide-pin size-4 rotate-45 text-n-slate-10"
          />
          <span
            v-if="hasUnread"
            class="inline-grid place-items-center h-5 min-w-5 px-1.5 rounded-full bg-[#25D366] dark:bg-[#21C063] text-[11px] font-bold leading-none text-white dark:text-[#0B141A]"
          >
            {{ unreadCount > 99 ? '99+' : unreadCount }}
          </span>
        </div>
      </div>

      <div
        v-if="
          owner ||
          (showInboxName && inbox.name) ||
          labels.length ||
          hasSla ||
          chat.meta?.sender?.id
        "
        class="flex items-center min-w-0 gap-1.5 overflow-hidden empty:hidden [&:not(:has(*))]:hidden"
      >
        <span
          v-if="owner"
          class="inline-flex items-center max-w-[55%] gap-1 py-px ltr:pl-px ltr:pr-1.5 rtl:pr-px rtl:pl-1.5 text-[11px] font-medium leading-4 rounded-full shrink-0"
          :class="{
            'bg-n-alpha-2 text-n-slate-11': owner.kind === 'agent',
            'bg-n-teal-3 text-n-teal-11': owner.kind === 'me',
            'bg-n-iris-3 text-n-iris-11': owner.kind === 'bot',
            'bg-n-amber-3 text-n-amber-11 !pl-1.5': owner.kind === 'none',
          }"
          data-owner-chip
        >
          <Avatar
            v-if="owner.kind === 'agent' || owner.kind === 'me'"
            :name="owner.name"
            :src="owner.thumbnail"
            :size="14"
            rounded-full
          />
          <span v-else-if="owner.kind === 'bot'" class="i-lucide-bot size-3" />
          <span v-else class="i-lucide-user-round-x size-3" />
          <span class="truncate">{{ owner.name }}</span>
        </span>
        <span
          v-if="showInboxName && inbox.name"
          class="text-[11px] truncate text-n-slate-10 min-w-0"
        >
          {{ inbox.name }}
        </span>
        <span
          v-for="label in shownLabels"
          :key="label.title"
          class="inline-flex items-center gap-1 text-[11px] text-n-slate-11 shrink-0 max-w-24"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :style="{ background: label.color }"
          />
          <span class="truncate">{{ label.title }}</span>
        </span>
        <span
          v-if="labels.length > shownLabels.length"
          class="text-[11px] text-n-slate-10 shrink-0"
        >
          +{{ labels.length - shownLabels.length }}
        </span>
        <SLACardLabel v-if="hasSla" :chat="chat" class="shrink-0" />
        <CrmValueChip
          :contact-id="chat.meta?.sender?.id"
          class="shrink-0 !text-[11px] !py-0"
        />
      </div>
    </div>
  </div>
</template>
