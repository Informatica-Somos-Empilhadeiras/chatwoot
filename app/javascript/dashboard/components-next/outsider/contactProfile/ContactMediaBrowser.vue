<script setup>
// OUTSIDER: "Mídia, links e docs" do painel do contato, como no WhatsApp: abas Mídia, Documentos e
// Links, agrupadas por mês ("Neste mês", "Setembro"...). Mostra a conversa aberta e, no botão de
// baixo, as mídias de todas as conversas do contato (anexos do contato no Chatwoot). Clicar numa
// mídia abre o visualizador com a fila de miniaturas; o documento abre em outra aba.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { jumpToMessage } from 'dashboard/composables/outsider/useConversationHistory';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MediaViewer from '../mediaViewer/MediaViewer.vue';
import {
  isViewable,
  groupByMonth,
  fileNameOf,
  formatSize,
} from '../mediaViewer/mediaHelpers';
import { useConversationLinks } from './useConversationLinks';
import {
  canViewInChatwoot,
  extensionOf as documentExtension,
} from 'dashboard/helper/outsider/documentFile';
import { openAttachmentInViewer } from '../fileViewer/fileViewerStore';

const props = defineProps({
  contactId: { type: Number, default: null },
  chat: { type: Object, default: () => ({}) },
  initialTab: { type: String, default: 'media' },
});

const emit = defineEmits(['back']);

const { t, locale } = useI18n();
const store = useStore();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const chatAttachments = useMapGetter('getSelectedChatAttachments');
const contactAttachmentsOf = useMapGetter('contacts/getContactAttachments');
const contactUiFlags = useMapGetter('contacts/getUIFlags');

const tab = ref(props.initialTab);
const allConversations = ref(false);

watch(allConversations, value => {
  if (value && props.contactId) {
    store.dispatch('contacts/fetchAttachments', props.contactId);
  }
});

const source = computed(() =>
  allConversations.value
    ? contactAttachmentsOf.value(props.contactId)
    : chatAttachments.value
);
const isLoading = computed(
  () => allConversations.value && contactUiFlags.value.isFetchingAttachments
);

const media = computed(() => source.value.filter(isViewable));
const documents = computed(() =>
  source.value.filter(item => item.file_type === 'file' && item.data_url)
);
const links = useConversationLinks(computed(() => props.chat));

const groupOptions = computed(() => ({
  locale: locale.value,
  thisMonth: t('OUTSIDER_WHATSAPP.PROFILE.THIS_MONTH'),
}));
const mediaGroups = computed(() => groupByMonth(media.value, groupOptions.value));
const documentGroups = computed(() =>
  groupByMonth(documents.value, groupOptions.value)
);

const TABS = computed(() => [
  { key: 'media', label: t('OUTSIDER_WHATSAPP.PROFILE.TABS.MEDIA'), count: media.value.length },
  { key: 'docs', label: t('OUTSIDER_WHATSAPP.PROFILE.TABS.DOCS'), count: documents.value.length },
  { key: 'links', label: t('OUTSIDER_WHATSAPP.PROFILE.TABS.LINKS'), count: links.value.length },
]);

const viewer = ref(null);
const openViewer = item => {
  viewer.value = item;
};

// PDF, Word, Excel, PowerPoint e texto abrem no visualizador do Chatwoot; o resto baixa
const openDocument = item => {
  if (canViewInChatwoot(documentExtension(item))) openAttachmentInViewer(item);
  else window.open(item.data_url, '_blank', 'noopener,noreferrer');
};

const goToMessage = (messageId, conversationId) => {
  if (!messageId) return;
  if (!conversationId || conversationId === props.chat?.id) {
    jumpToMessage(messageId);
    return;
  }
  router.push({
    name: 'inbox_conversation',
    params: { accountId: accountId.value, conversation_id: conversationId },
    query: { messageId },
  });
};

const DOC_COLORS = {
  pdf: 'bg-[#E5484D]',
  doc: 'bg-[#2B579A]',
  docx: 'bg-[#2B579A]',
  xls: 'bg-[#217346]',
  xlsx: 'bg-[#217346]',
  csv: 'bg-[#217346]',
  ppt: 'bg-[#D24726]',
  pptx: 'bg-[#D24726]',
  zip: 'bg-[#7C3AED]',
};
const extensionOf = item =>
  (item.extension || fileNameOf(item).split('.').pop() || '').toLowerCase();
const docDate = item =>
  item.created_at
    ? new Date(item.created_at * 1000).toLocaleDateString(
        String(locale.value).replace('_', '-')
      )
    : '';
</script>

<template>
  <div class="flex flex-col min-h-full" data-media-browser>
    <div
      class="sticky top-0 z-10 flex items-center gap-2 px-2 h-14 bg-n-surface-2 border-b border-n-weak"
    >
      <button
        type="button"
        class="grid rounded-full size-9 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
        data-media-back
        @click="emit('back')"
      >
        <span class="ltr:i-lucide-arrow-left rtl:i-lucide-arrow-right size-5" />
      </button>
      <span class="text-[15px] font-semibold text-n-slate-12">
        {{ t('OUTSIDER_WHATSAPP.PROFILE.MEDIA_TITLE') }}
      </span>
    </div>

    <div class="flex border-b border-n-weak">
      <button
        v-for="item in TABS"
        :key="item.key"
        type="button"
        class="relative flex-1 py-3 text-sm font-medium transition-colors"
        :class="
          tab === item.key
            ? 'text-n-slate-12 after:absolute after:inset-x-3 after:bottom-0 after:h-[3px] after:rounded-full after:bg-[#25D366]'
            : 'text-n-slate-10 hover:text-n-slate-12'
        "
        @click="tab = item.key"
      >
        {{ item.label }}
      </button>
    </div>

    <div class="flex-1 px-3 py-3">
      <div v-if="isLoading" class="flex justify-center py-6">
        <Spinner class="size-5" />
      </div>

      <template v-else-if="tab === 'media'">
        <p
          v-if="!media.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          {{ t('OUTSIDER_WHATSAPP.PROFILE.EMPTY.MEDIA') }}
        </p>
        <section
          v-for="group in mediaGroups"
          :key="group.key"
          class="mb-4"
        >
          <h4
            class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            {{ group.label }}
          </h4>
          <div class="grid grid-cols-3 gap-1">
            <button
              v-for="item in group.items"
              :key="item.id"
              type="button"
              class="relative !p-0 overflow-hidden rounded-md aspect-square bg-n-alpha-2 group"
              data-media-tile
              @click="openViewer(item)"
            >
              <img
                v-if="item.file_type === 'image'"
                :src="item.thumb_url || item.data_url"
                loading="lazy"
                class="object-cover transition-transform size-full group-hover:scale-105"
              />
              <template v-else-if="item.file_type !== 'audio'">
                <video
                  :src="item.data_url"
                  preload="metadata"
                  muted
                  class="object-cover pointer-events-none size-full"
                />
                <span
                  class="absolute grid rounded-full bottom-1 left-1 size-6 place-items-center bg-black/50 text-white"
                >
                  <span class="i-lucide-play size-3.5" />
                </span>
              </template>
              <span
                v-else
                class="grid text-white size-full place-items-center bg-[#F59E0B]"
              >
                <span class="i-lucide-headphones size-7" />
              </span>
            </button>
          </div>
        </section>
      </template>

      <template v-else-if="tab === 'docs'">
        <p
          v-if="!documents.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          {{ t('OUTSIDER_WHATSAPP.PROFILE.EMPTY.DOCS') }}
        </p>
        <section
          v-for="group in documentGroups"
          :key="group.key"
          class="mb-4"
        >
          <h4
            class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            {{ group.label }}
          </h4>
          <div class="flex flex-col gap-1">
            <div
              v-for="item in group.items"
              :key="item.id"
              class="flex items-center gap-3 p-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
              @click="openDocument(item)"
            >
              <span
                class="grid text-[10px] font-bold text-white uppercase rounded-md size-10 shrink-0 place-items-center"
                :class="DOC_COLORS[extensionOf(item)] || 'bg-n-slate-9'"
              >
                {{ extensionOf(item).slice(0, 4) || 'doc' }}
              </span>
              <span class="flex flex-col flex-1 min-w-0">
                <span class="text-sm truncate text-n-slate-12">
                  {{ fileNameOf(item) }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ [formatSize(item.file_size), docDate(item)].filter(Boolean).join(' · ') }}
                </span>
              </span>
              <button
                v-tooltip.left="t('OUTSIDER_WHATSAPP.VIEWER.GO_TO_MESSAGE')"
                type="button"
                class="grid rounded-full size-8 shrink-0 place-items-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                @click.stop="goToMessage(item.message_id, item.conversation_id)"
              >
                <span class="i-lucide-message-square-text size-4" />
              </button>
            </div>
          </div>
        </section>
      </template>

      <template v-else>
        <p
          v-if="!links.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          {{ t('OUTSIDER_WHATSAPP.PROFILE.EMPTY.LINKS') }}
        </p>
        <div class="flex flex-col gap-1">
          <a
            v-for="link in links"
            :key="link.url"
            :href="link.url"
            target="_blank"
            rel="noopener noreferrer nofollow"
            class="flex items-start gap-3 p-2 rounded-lg hover:bg-n-alpha-1"
          >
            <span
              class="grid rounded-md size-10 shrink-0 place-items-center bg-n-alpha-2 text-n-slate-11"
            >
              <span class="i-lucide-link size-5" />
            </span>
            <span class="flex flex-col flex-1 min-w-0">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ link.host }}
              </span>
              <span class="text-xs truncate text-n-blue-11">{{ link.url }}</span>
              <span v-if="link.text" class="text-xs truncate text-n-slate-10">
                {{ link.text }}
              </span>
            </span>
          </a>
        </div>
      </template>
    </div>

    <button
      v-if="contactId && tab !== 'links'"
      type="button"
      class="sticky bottom-0 flex items-center justify-center gap-2 py-3 text-sm font-medium border-t text-[#1DAA61] dark:text-[#21C063] border-n-weak bg-n-surface-2 hover:bg-n-alpha-1"
      data-media-scope
      @click="allConversations = !allConversations"
    >
      <span
        :class="allConversations ? 'i-lucide-message-square' : 'i-lucide-images'"
        class="size-4"
      />
      {{
        allConversations
          ? t('OUTSIDER_WHATSAPP.PROFILE.ONLY_THIS')
          : t('OUTSIDER_WHATSAPP.PROFILE.ALL_CONVERSATIONS')
      }}
    </button>

    <MediaViewer
      v-if="viewer"
      :show="!!viewer"
      :attachment="viewer"
      :all-attachments="media"
      auto-play
      @close="viewer = null"
    />
  </div>
</template>
