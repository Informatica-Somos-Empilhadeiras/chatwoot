<script setup>
// OUTSIDER: documento no estilo WhatsApp (PDF, Word, Excel, PowerPoint, planilha, texto, zip...). Em cima, a miniatura
// com o começo do arquivo (primeira página do PDF, começo do texto, primeiras linhas da planilha, 1º slide); embaixo,
// o ícone com a cor do tipo, o nome, "2 páginas · PDF · 35 KB" e o botãozinho de baixar. Clicar na miniatura ou no
// nome abre o visualizador completo dentro do Chatwoot (só para ler). Tipo sem miniatura nem visualização (zip...)
// fica só com a linha do arquivo e baixa ao clicar. A miniatura só é buscada quando o cartão aparece na tela.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntersectionObserver } from '@vueuse/core';
import BaseBubble from '../bubbles/Base.vue';
import { useMessageContext } from '../provider.js';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { formatSize } from 'dashboard/components-next/outsider/mediaViewer/mediaHelpers';
import {
  canViewInChatwoot,
  docColor,
  extensionOf,
  fileNameOf,
} from 'dashboard/helper/outsider/documentFile';
import { canPeek, documentPeek } from 'dashboard/helper/outsider/documentPeek';
import { openAttachmentInViewer } from 'dashboard/components-next/outsider/fileViewer/fileViewerStore';
import FilePeek from 'dashboard/components-next/outsider/fileViewer/FilePeek.vue';

const SLIDES = ['pptx', 'pptm', 'ppsx', 'potx'];

const { attachments, content } = useMessageContext();
const { t } = useI18n();

const attachment = computed(() => attachments.value[0] || {});
const name = computed(
  () => fileNameOf(attachment.value) || t('CONVERSATION.UNKNOWN_FILE_TYPE')
);
const ext = computed(() => extensionOf(attachment.value));
const viewable = computed(() => canViewInChatwoot(ext.value));
const downloadUrl = computed(() => attachment.value.dataUrl);

const card = ref(null);
const peek = ref(null);
const peekState = ref(canPeek(ext.value) ? 'waiting' : 'none');
const showPeek = computed(() =>
  ['waiting', 'loading', 'ready'].includes(peekState.value)
);

const loadPeek = async () => {
  if (peekState.value !== 'waiting' || !attachment.value.id) return;
  peekState.value = 'loading';
  try {
    const data = await documentPeek(attachment.value.id, ext.value);
    peek.value = data;
    peekState.value = data?.type && data.type !== 'none' ? 'ready' : 'none';
  } catch (error) {
    peekState.value = 'none';
  }
};

const { stop } = useIntersectionObserver(
  card,
  ([entry]) => {
    if (!entry?.isIntersecting) return;
    stop();
    loadPeek();
  },
  { rootMargin: '300px' }
);

const pagesText = computed(() => {
  const count = peek.value?.pages;
  if (!count) return '';
  return SLIDES.includes(ext.value)
    ? t('OUTSIDER_WHATSAPP.DOCUMENT.SLIDES', { count }, count)
    : t('OUTSIDER_WHATSAPP.DOCUMENT.PAGES', { count }, count);
});

const meta = computed(() =>
  [
    pagesText.value,
    ext.value.toUpperCase(),
    formatSize(attachment.value.fileSize),
  ]
    .filter(Boolean)
    .join(' · ')
);

// legenda (a Evolution às vezes repete o nome do arquivo como texto)
const caption = computed(() => {
  const text = String(content.value || '').trim();
  if (!text || text === name.value) return '';
  return new MessageFormatter(text).formattedMessage;
});

const view = () => {
  if (viewable.value) openAttachmentInViewer(attachment.value);
  else window.open(downloadUrl.value, '_blank', 'noopener,noreferrer');
};
</script>

<template>
  <BaseBubble
    ref="card"
    class="p-1 w-80 max-w-full"
    data-bubble-name="document"
  >
    <button
      v-if="showPeek"
      type="button"
      class="block w-full h-[150px] overflow-hidden rounded-lg border border-n-alpha-black1"
      :title="t('OUTSIDER_WHATSAPP.DOCUMENT.OPEN', { name })"
      data-document-view
      @click="view"
    >
      <FilePeek :peek="peek" :loading="peekState !== 'ready'" />
    </button>
    <div
      class="flex items-center gap-2.5 px-2 py-2 rounded-lg bg-n-alpha-black1"
      :class="showPeek ? 'mt-1' : ''"
    >
      <button
        type="button"
        class="flex items-center flex-1 min-w-0 gap-2.5 text-start"
        :title="name"
        :data-document-view="showPeek ? undefined : ''"
        @click="view"
      >
        <span
          class="grid w-8 h-10 rounded-md text-[9px] font-bold text-white uppercase place-items-center shrink-0"
          :style="{ background: docColor(ext) }"
        >
          {{ ext.slice(0, 4) || 'doc' }}
        </span>
        <span class="flex flex-col flex-1 min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ name }}
          </span>
          <span class="text-xs truncate text-n-slate-11">{{ meta }}</span>
        </span>
      </button>
      <a
        :href="downloadUrl"
        target="_blank"
        rel="noopener noreferrer"
        download
        class="grid border rounded-full size-8 place-items-center shrink-0 border-n-slate-7 text-n-slate-11 hover:bg-n-alpha-black2 hover:text-n-slate-12"
        :title="t('OUTSIDER_WHATSAPP.DOCUMENT.DOWNLOAD')"
        :aria-label="t('OUTSIDER_WHATSAPP.DOCUMENT.DOWNLOAD')"
        data-document-download
      >
        <span class="i-lucide-download size-4" />
      </a>
    </div>
    <div
      v-if="caption"
      v-dompurify-html="caption"
      class="px-2 pt-2 prose prose-bubble break-words"
    />
  </BaseBubble>
</template>
