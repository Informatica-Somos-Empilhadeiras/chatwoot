<script setup>
// OUTSIDER: topo do painel do contato no estilo WhatsApp/Telegram ("Dados do contato"): foto
// grande com o selo do canal, nome, telefone/e-mail e de onde a conversa veio, atalhos (buscar na
// conversa, fixar, copiar, perfil completo) e a faixa "Mídia, links e docs". As informações que o
// Chatwoot já mostrava (ContactInfo, atributos, conversas anteriores, CRM...) continuam abaixo.
// Ao abrir "Mídia, links e docs" o resto do painel some (CSS :has em whatsappLook.css).
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { parsePhoneNumberFromString } from 'libphonenumber-js';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useConversationPins } from 'dashboard/composables/outsider/useConversationPins';
import { openSearch } from 'dashboard/composables/outsider/useConversationHistory';
import { channelBadge } from 'dashboard/helper/outsider/channelBadge';
import ChannelAvatar from '../whatsappLook/ChannelAvatar.vue';
import ContactMediaBrowser from './ContactMediaBrowser.vue';
import MediaViewer from '../mediaViewer/MediaViewer.vue';
import { isViewable } from '../mediaViewer/mediaHelpers';
import { useConversationLinks } from './useConversationLinks';

const props = defineProps({
  contact: { type: Object, default: () => ({}) },
  chat: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const inboxGetter = useMapGetter('inboxes/getInbox');
const chatAttachments = useMapGetter('getSelectedChatAttachments');
const { isPinned, togglePin } = useConversationPins();

const browserTab = ref(null);
watch(
  () => props.chat?.id,
  () => {
    browserTab.value = null;
  }
);

const inbox = computed(() => inboxGetter.value(props.chat?.inbox_id) || {});
const badge = computed(() => channelBadge(inbox.value));
const isGroup = computed(() =>
  String(props.contact.identifier || '').endsWith('@g.us')
);

const phone = computed(() => {
  const raw = props.contact.phone_number;
  if (!raw) return '';
  return parsePhoneNumberFromString(raw)?.formatInternational() || raw;
});
const mainLine = computed(() => phone.value || props.contact.email || '');
const origin = computed(() =>
  [
    isGroup.value ? t('OUTSIDER_WHATSAPP.PROFILE.GROUP') : badge.value?.label,
    inbox.value.name,
  ]
    .filter(Boolean)
    .join(' · ')
);
const company = computed(
  () => props.contact.additional_attributes?.company_name || ''
);

const pinned = computed(() => !!props.chat?.id && isPinned(props.chat.id));

const media = computed(() => chatAttachments.value.filter(isViewable));
const documents = computed(() =>
  chatAttachments.value.filter(item => item.file_type === 'file')
);
const links = useConversationLinks(computed(() => props.chat));
const linkCount = computed(() => links.value.length);
const totalCount = computed(
  () => media.value.length + documents.value.length + linkCount.value
);
const preview = computed(() =>
  [...media.value]
    .sort((a, b) => (b.created_at || 0) - (a.created_at || 0))
    .slice(0, 4)
);

const viewer = ref(null);

const copyMain = async () => {
  if (!mainLine.value) return;
  await copyTextToClipboard(props.contact.phone_number || props.contact.email);
  useAlert(t('OUTSIDER_WHATSAPP.PROFILE.COPIED'));
};

const openProfile = () => {
  const route = router.resolve({
    name: 'contacts_edit',
    params: { accountId: accountId.value, contactId: props.contact.id },
  });
  window.open(route.href, '_blank', 'noopener');
};

const ACTIONS = computed(() => [
  {
    key: 'search',
    icon: 'i-lucide-search',
    label: t('OUTSIDER_WHATSAPP.PROFILE.ACTIONS.SEARCH'),
    show: !!props.chat?.id,
    run: openSearch,
  },
  {
    key: 'pin',
    icon: pinned.value ? 'i-lucide-pin-off' : 'i-lucide-pin',
    label: pinned.value
      ? t('OUTSIDER_WHATSAPP.PROFILE.ACTIONS.UNPIN')
      : t('OUTSIDER_WHATSAPP.PROFILE.ACTIONS.PIN'),
    show: !!props.chat?.id,
    run: () => togglePin(props.chat.id),
  },
  {
    key: 'copy',
    icon: 'i-lucide-copy',
    label: phone.value
      ? t('OUTSIDER_WHATSAPP.PROFILE.ACTIONS.COPY_PHONE')
      : t('OUTSIDER_WHATSAPP.PROFILE.ACTIONS.COPY_EMAIL'),
    show: !!mainLine.value,
    run: copyMain,
  },
  {
    key: 'profile',
    icon: 'i-lucide-id-card',
    label: t('OUTSIDER_WHATSAPP.PROFILE.ACTIONS.PROFILE'),
    show: !!props.contact.id,
    run: openProfile,
  },
]);
const visibleActions = computed(() => ACTIONS.value.filter(item => item.show));
</script>

<template>
  <div
    class="outsider-contact-hero"
    :data-media-open="browserTab ? 'true' : null"
  >
    <ContactMediaBrowser
      v-if="browserTab"
      :contact-id="contact.id"
      :chat="chat"
      :initial-tab="browserTab"
      @back="browserTab = null"
    />
    <template v-else>
      <div class="flex items-center gap-2 px-2 h-14">
        <button
          type="button"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
          data-profile-close
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
        <span class="text-[15px] font-semibold text-n-slate-12">
          {{ t('OUTSIDER_WHATSAPP.PROFILE.TITLE') }}
        </span>
      </div>

      <div class="flex flex-col items-center px-4 pt-2 pb-5 text-center">
        <ChannelAvatar
          :name="contact.name || ''"
          :src="contact.thumbnail || ''"
          :inbox="inbox"
          :size="112"
        />
        <h2
          class="mt-4 mb-0 text-xl font-semibold break-words text-n-slate-12"
        >
          {{ contact.name }}
        </h2>
        <span
          v-if="mainLine"
          class="mt-1 text-base text-n-slate-11 tabular-nums"
          data-profile-main
        >
          {{ mainLine }}
        </span>
        <span v-if="company" class="mt-0.5 text-sm text-n-slate-10">
          {{ company }}
        </span>
        <span
          v-if="origin"
          class="inline-flex items-center gap-1.5 mt-2 text-sm font-medium"
          :style="{ color: badge?.kind === 'whatsapp' ? '#1DAA61' : undefined }"
          :class="{ 'text-n-slate-11': badge?.kind !== 'whatsapp' }"
        >
          <span v-if="badge" :class="badge.icon" class="size-4" />
          {{ origin }}
        </span>

        <div
          v-if="visibleActions.length"
          class="grid w-full gap-2 mt-5"
          :style="{
            gridTemplateColumns: `repeat(${visibleActions.length}, minmax(0, 1fr))`,
          }"
        >
          <button
            v-for="action in visibleActions"
            :key="action.key"
            type="button"
            class="flex flex-col items-center gap-1.5 py-2.5 rounded-xl bg-n-alpha-1 dark:bg-n-alpha-2 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-3 text-n-slate-12 transition-colors"
            :data-profile-action="action.key"
            @click="action.run"
          >
            <span :class="action.icon" class="size-5 text-[#1DAA61] dark:text-[#21C063]" />
            <span class="text-xs font-medium leading-tight">
              {{ action.label }}
            </span>
          </button>
        </div>
      </div>

      <div class="px-2 pb-2">
        <button
          type="button"
          class="flex items-center w-full gap-3 px-3 pt-3 pb-1 rounded-t-xl hover:bg-n-alpha-1"
          data-profile-media
          @click="browserTab = 'media'"
        >
          <span class="i-lucide-images size-5 text-n-slate-10" />
          <span class="flex-1 text-sm font-medium text-left text-n-slate-12">
            {{ t('OUTSIDER_WHATSAPP.PROFILE.MEDIA_TITLE') }}
          </span>
          <span class="text-sm text-n-slate-10 tabular-nums">
            {{ totalCount }}
          </span>
          <span
            class="ltr:i-lucide-chevron-right rtl:i-lucide-chevron-left size-4 text-n-slate-10"
          />
        </button>
        <div
          v-if="preview.length"
          class="grid grid-cols-4 gap-1.5 px-3 pt-2 pb-3"
        >
          <button
            v-for="item in preview"
            :key="item.id"
            type="button"
            class="relative !p-0 overflow-hidden rounded-lg aspect-square bg-n-alpha-2"
            @click="viewer = item"
          >
            <img
              v-if="item.file_type === 'image'"
              :src="item.thumb_url || item.data_url"
              loading="lazy"
              class="object-cover size-full"
            />
            <template v-else-if="item.file_type !== 'audio'">
              <video
                :src="item.data_url"
                preload="metadata"
                muted
                class="object-cover pointer-events-none size-full"
              />
              <span class="absolute inset-0 grid place-items-center text-white">
                <span class="i-lucide-play size-5 drop-shadow" />
              </span>
            </template>
            <span
              v-else
              class="grid text-white size-full place-items-center bg-[#F59E0B]"
            >
              <span class="i-lucide-headphones size-5" />
            </span>
          </button>
        </div>
        <div
          v-else
          class="flex gap-2 px-3 pt-1 pb-3 text-xs text-n-slate-10"
        >
          <button
            v-if="documents.length"
            type="button"
            class="underline"
            @click="browserTab = 'docs'"
          >
            {{ t('OUTSIDER_WHATSAPP.PROFILE.TABS.DOCS') }} ({{ documents.length }})
          </button>
          <button
            v-if="linkCount"
            type="button"
            class="underline"
            @click="browserTab = 'links'"
          >
            {{ t('OUTSIDER_WHATSAPP.PROFILE.TABS.LINKS') }} ({{ linkCount }})
          </button>
          <span v-if="!documents.length && !linkCount">
            {{ t('OUTSIDER_WHATSAPP.PROFILE.EMPTY.MEDIA') }}
          </span>
        </div>
      </div>
      <div class="mx-4 border-b border-n-weak" />
    </template>

    <MediaViewer
      v-if="viewer"
      :show="!!viewer"
      :attachment="viewer"
      :all-attachments="media"
      @close="viewer = null"
    />
  </div>
</template>
