<script setup>
// OUTSIDER: segunda linha do card da conversa, como no WhatsApp: ✓✓ da última mensagem enviada,
// "Nome:" de quem falou no grupo, ícone e nome do anexo ("📷 Foto") e "digitando..." em verde.
// Recebe a mensagem como vem da lista (snake_case).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { outsiderPreview } from 'dashboard/helper/outsider/messagePreview';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';

const props = defineProps({
  message: { type: Object, default: null },
  typingName: { type: String, default: '' },
  isGroup: { type: Boolean, default: false },
});

const { t } = useI18n();
const { getPlainText } = useMessageFormatter();

const ATTACHMENT_ICONS = {
  image: 'i-lucide-camera',
  video: 'i-lucide-video',
  audio: 'i-lucide-mic',
  file: 'i-lucide-file-text',
  location: 'i-lucide-map-pin',
  contact: 'i-lucide-user-round',
  fallback: 'i-lucide-paperclip',
  share: 'i-lucide-share-2',
  story_mention: 'i-lucide-circle-dashed',
  ig_reel: 'i-lucide-clapperboard',
};

const STATUS_ICONS = {
  progress: { icon: 'i-lucide-clock-3', class: 'text-n-slate-10' },
  sent: { icon: 'i-lucide-check', class: 'text-n-slate-10' },
  delivered: { icon: 'i-lucide-check-check', class: 'text-n-slate-10' },
  read: { icon: 'i-lucide-check-check', class: 'text-[#53BDEB]' },
  failed: { icon: 'i-lucide-circle-alert', class: 'text-n-ruby-10' },
};

const isOutgoing = computed(() => props.message?.message_type === 1);
const isActivity = computed(() => props.message?.message_type === 2);
const isPrivate = computed(() => !!props.message?.private);

const statusIcon = computed(() => {
  if (!isOutgoing.value || isPrivate.value) return null;
  return STATUS_ICONS[props.message.status] || STATUS_ICONS.sent;
});

const parts = computed(() => splitSenderHeader(props.message?.content || ''));

// no grupo a Evolution manda "**+55 62 9999-0000 - Nome:**": fica só o nome
const senderName = computed(() => {
  const { header } = parts.value;
  if (header) {
    const [, name] = header.split(/\s+-\s+/);
    return (name || header).trim();
  }
  if (props.isGroup && !isOutgoing.value && !isActivity.value) {
    return props.message?.sender?.name || '';
  }
  return '';
});

const attachment = computed(() => {
  const list = props.message?.attachments || [];
  if (!list.length) return null;
  const type = list[0].file_type;
  const same = list.filter(item => item.file_type === type).length;
  const labelKey = `CHAT_LIST.ATTACHMENTS.${type}.CONTENT`;
  return {
    icon: ATTACHMENT_ICONS[type] || ATTACHMENT_ICONS.fallback,
    label:
      same > 1 && ['image', 'video'].includes(type)
        ? t(`OUTSIDER_WHATSAPP.LOOK.MEDIA_COUNT.${type}`, { count: same })
        : t(labelKey) !== labelKey
          ? t(labelKey)
          : t('CHAT_LIST.ATTACHMENTS.file.CONTENT'),
  };
});

// encaminhada por nós: "*[Mensagem Encaminhada]*" vira a setinha de encaminhar, como no WhatsApp
const forwardHeader = computed(() => {
  const label = t('OUTSIDER_WHATSAPP.FORWARD.HEADER').replace(
    /[.*+?^${}()|[\]\\]/g,
    '\\$&'
  );
  return new RegExp(`^\\*?${label}\\*?\\s*`);
});
const isForwarded = computed(() =>
  forwardHeader.value.test(parts.value.body)
);

const text = computed(() => {
  const message = props.message;
  if (!message) return '';
  const special = outsiderPreview(message);
  if (special) return special;
  const subject = message.content_attributes?.email?.subject;
  const body = subject || parts.value.body.replace(forwardHeader.value, '');
  return body ? getPlainText(body) : '';
});
</script>

<template>
  <div
    class="flex items-center min-w-0 gap-1 overflow-hidden whitespace-nowrap"
  >
    <span v-if="typingName" class="truncate font-medium text-[#1DAA61]">
      {{
        isGroup
          ? t('OUTSIDER_WHATSAPP.LOOK.TYPING_NAME', { name: typingName })
          : t('OUTSIDER_WHATSAPP.LOOK.TYPING')
      }}
    </span>
    <template v-else-if="message">
      <span
        v-if="isPrivate"
        class="inline-flex items-center gap-0.5 shrink-0 font-medium text-n-amber-11"
      >
        <span class="i-lucide-lock size-3.5" />
        {{ t('OUTSIDER_WHATSAPP.LOOK.NOTE') }}
      </span>
      <span
        v-else-if="statusIcon"
        :class="[statusIcon.icon, statusIcon.class]"
        class="size-4 shrink-0"
      />
      <span
        v-if="senderName && !isPrivate"
        class="shrink-0 max-w-[45%] truncate"
      >
        {{ senderName }}:
      </span>
      <span
        v-if="isForwarded && !isPrivate"
        class="i-lucide-forward size-4 shrink-0 text-n-slate-10"
      />
      <span
        v-if="attachment"
        :class="attachment.icon"
        class="size-4 shrink-0 text-n-slate-10"
      />
      <span class="truncate" :class="{ italic: isActivity }">
        {{ text || attachment?.label || t('CHAT_LIST.NO_CONTENT') }}
      </span>
    </template>
    <span v-else class="truncate italic">
      {{ t('CHAT_LIST.NO_MESSAGES') }}
    </span>
  </div>
</template>
