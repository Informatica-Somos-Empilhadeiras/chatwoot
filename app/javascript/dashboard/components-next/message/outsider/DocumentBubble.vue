<script setup>
// OUTSIDER: documento no estilo WhatsApp (PDF, Word, Excel, PowerPoint, planilha, zip...): ícone com a cor do tipo,
// nome, tipo e tamanho, e os botões Visualizar (abre dentro do Chatwoot, só para ler) e Baixar. A legenda, quando
// tem, fica embaixo. Clicar no cartão visualiza; tipo que não dá para visualizar baixa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
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
import { openAttachmentInViewer } from 'dashboard/components-next/outsider/fileViewer/fileViewerStore';

const { attachments, content } = useMessageContext();
const { t } = useI18n();

const attachment = computed(() => attachments.value[0] || {});
const name = computed(
  () => fileNameOf(attachment.value) || t('CONVERSATION.UNKNOWN_FILE_TYPE')
);
const ext = computed(() => extensionOf(attachment.value));
const meta = computed(() =>
  [ext.value.toUpperCase(), formatSize(attachment.value.fileSize)]
    .filter(Boolean)
    .join(' · ')
);
const viewable = computed(() => canViewInChatwoot(ext.value));
const downloadUrl = computed(() => attachment.value.dataUrl);

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
  <BaseBubble class="p-1.5 w-80 max-w-full" data-bubble-name="document">
    <button
      type="button"
      class="flex items-center w-full gap-3 p-2.5 rounded-lg bg-n-alpha-black1 text-start hover:bg-n-alpha-black2"
      :title="name"
      @click="view"
    >
      <span
        class="grid w-9 h-11 rounded-md text-[10px] font-bold text-white uppercase place-items-center shrink-0"
        :style="{ background: docColor(ext) }"
      >
        {{ ext.slice(0, 4) || 'doc' }}
      </span>
      <span class="flex flex-col flex-1 min-w-0">
        <span class="text-sm font-medium truncate text-n-slate-12">{{
          name
        }}</span>
        <span class="text-xs text-n-slate-11">{{ meta }}</span>
      </span>
    </button>
    <div class="flex gap-1.5 px-1 pt-1.5">
      <button
        v-if="viewable"
        type="button"
        class="flex items-center justify-center flex-1 gap-1.5 h-8 text-xs font-medium rounded-md text-n-slate-12 bg-n-alpha-black1 hover:bg-n-alpha-black2"
        data-document-view
        @click="view"
      >
        <span class="i-lucide-eye size-4" />
        {{ t('OUTSIDER_WHATSAPP.DOCUMENT.VIEW') }}
      </button>
      <a
        :href="downloadUrl"
        target="_blank"
        rel="noopener noreferrer"
        download
        class="flex items-center justify-center flex-1 gap-1.5 h-8 text-xs font-medium rounded-md text-n-slate-12 bg-n-alpha-black1 hover:bg-n-alpha-black2"
      >
        <span class="i-lucide-download size-4" />
        {{ t('OUTSIDER_WHATSAPP.DOCUMENT.DOWNLOAD') }}
      </a>
    </div>
    <div
      v-if="caption"
      v-dompurify-html="caption"
      class="px-2 pt-2 prose prose-bubble break-words"
    />
  </BaseBubble>
</template>
