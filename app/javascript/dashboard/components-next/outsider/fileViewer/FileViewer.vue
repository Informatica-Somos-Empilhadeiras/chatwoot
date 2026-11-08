<script setup>
// OUTSIDER: janela que mostra um documento dentro do Chatwoot, só para ler: PDF e texto no navegador, Word, Excel
// e PowerPoint pelo visualizador do Office na web (anexos das conversas) ou pela visualização do OneDrive/SharePoint
// (arquivos do Teams). Para editar, "Editar no Office" abre o arquivo em outra aba. Esc ou clique fora fecha.
// No celular o PDF abre no visualizador do aparelho (o navegador do celular não mostra PDF dentro da página).
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { formatSize } from 'dashboard/components-next/outsider/mediaViewer/mediaHelpers';
import { docColor } from 'dashboard/helper/outsider/documentFile';
import { fileViewer, closeFileViewer } from './fileViewerStore';

const { t } = useI18n();

const file = computed(() => fileViewer.file || {});
const ext = computed(() => String(file.value.extension || '').toLowerCase());
const meta = computed(() =>
  [ext.value.toUpperCase(), formatSize(file.value.size)].filter(Boolean).join(' · ')
);

const touch =
  typeof window !== 'undefined' &&
  window.matchMedia?.('(pointer: coarse)').matches &&
  window.innerWidth < 1024;

const framed = computed(
  () =>
    ['pdf', 'office', 'text', 'preview'].includes(file.value.kind) &&
    !!file.value.viewUrl &&
    !(touch && file.value.kind === 'pdf')
);
const isImage = computed(() => file.value.kind === 'image' && !!file.value.viewUrl);
const isVideo = computed(() => file.value.kind === 'video' && !!file.value.viewUrl);
const canOpenTab = computed(
  () => ['pdf', 'text'].includes(file.value.kind) && !!file.value.viewUrl
);

const frameLoading = ref(true);
watch(
  () => file.value.viewUrl,
  () => {
    frameLoading.value = true;
  }
);

const reasonText = computed(() => {
  if (fileViewer.error) return t('OUTSIDER_WHATSAPP.FILE_VIEWER.REASONS.LOAD');
  if (touch && file.value.kind === 'pdf') return t('OUTSIDER_WHATSAPP.FILE_VIEWER.MOBILE_PDF');
  const reason = String(file.value.reason || 'unsupported').toUpperCase();
  const key = `OUTSIDER_WHATSAPP.FILE_VIEWER.REASONS.${reason}`;
  const text = t(key);
  return text === key ? t('OUTSIDER_WHATSAPP.FILE_VIEWER.REASONS.UNSUPPORTED') : text;
});

const openTab = () => {
  if (file.value.viewUrl) window.open(file.value.viewUrl, '_blank', 'noopener,noreferrer');
};

const onKey = event => {
  if (event.key === 'Escape' && fileViewer.open) {
    event.stopPropagation();
    closeFileViewer();
  }
};
watch(
  () => fileViewer.open,
  open => {
    if (open) window.addEventListener('keydown', onKey, true);
    else window.removeEventListener('keydown', onKey, true);
  }
);
onBeforeUnmount(() => window.removeEventListener('keydown', onKey, true));
</script>

<template>
  <TeleportWithDirection v-if="fileViewer.open">
    <div
      class="fixed inset-0 z-[9999] flex flex-col text-white"
      style="background: #0b141a"
      data-outsider-file-viewer
      @click.self="closeFileViewer"
    >
      <header class="flex items-center gap-3 px-4 h-16 shrink-0">
        <span
          class="grid w-9 h-11 rounded-md text-[10px] font-bold uppercase place-items-center shrink-0"
          :style="{ background: docColor(ext) }"
        >
          {{ ext.slice(0, 4) || 'doc' }}
        </span>
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-[15px] font-medium truncate" :title="file.name">
            {{ file.name }}
          </span>
          <span class="text-xs text-white/60">{{ meta }}</span>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <button
            v-if="canOpenTab"
            v-tooltip.bottom="t('OUTSIDER_WHATSAPP.FILE_VIEWER.OPEN_TAB')"
            type="button"
            class="file-viewer-btn"
            @click="openTab"
          >
            <span class="i-lucide-external-link size-5" />
          </button>
          <a
            v-if="file.editUrl"
            :href="file.editUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="flex items-center gap-2 px-3 h-9 rounded-full text-sm font-medium bg-white/10 hover:bg-white/20"
          >
            <span class="i-lucide-pencil size-4" />
            {{ t('OUTSIDER_WHATSAPP.FILE_VIEWER.EDIT') }}
          </a>
          <a
            v-if="file.downloadUrl"
            v-tooltip.bottom="t('OUTSIDER_WHATSAPP.FILE_VIEWER.DOWNLOAD')"
            :href="file.downloadUrl"
            target="_blank"
            rel="noopener noreferrer"
            download
            class="file-viewer-btn"
          >
            <span class="i-lucide-download size-5" />
          </a>
          <span class="w-px h-6 mx-1 bg-white/20" />
          <button
            v-tooltip.bottom="t('OUTSIDER_WHATSAPP.FILE_VIEWER.CLOSE')"
            type="button"
            class="file-viewer-btn"
            data-file-viewer-close
            @click="closeFileViewer"
          >
            <span class="i-lucide-x size-6" />
          </button>
        </div>
      </header>

      <main
        class="relative flex items-center justify-center flex-1 min-h-0 px-2 pb-3 sm:px-6"
        @click.self="closeFileViewer"
      >
        <div
          v-if="fileViewer.loading"
          class="flex flex-col items-center gap-3 text-white/70"
        >
          <span class="i-lucide-loader-circle animate-spin size-8" />
          <span class="text-sm">{{ t('OUTSIDER_WHATSAPP.FILE_VIEWER.LOADING') }}</span>
        </div>

        <template v-else-if="!fileViewer.error && framed">
          <div
            v-if="frameLoading"
            class="absolute inset-0 flex flex-col items-center justify-center gap-3 pointer-events-none text-white/70"
          >
            <span class="i-lucide-loader-circle animate-spin size-8" />
            <span class="text-sm">{{ t('OUTSIDER_WHATSAPP.FILE_VIEWER.LOADING') }}</span>
          </div>
          <iframe
            :key="file.viewUrl"
            :src="file.viewUrl"
            :title="file.name"
            class="w-full h-full max-w-6xl bg-white border-0 rounded-lg shadow-2xl"
            :class="{ 'opacity-0': frameLoading }"
            allow="fullscreen"
            @load="frameLoading = false"
          />
        </template>

        <img
          v-else-if="!fileViewer.error && isImage"
          :src="file.viewUrl"
          :alt="file.name"
          class="object-contain max-w-full max-h-full shadow-2xl"
        />
        <video
          v-else-if="!fileViewer.error && isVideo"
          :src="file.viewUrl"
          controls
          playsinline
          class="max-w-full max-h-full"
        />

        <div
          v-else
          class="flex flex-col items-center max-w-md gap-4 px-6 py-8 text-center rounded-2xl bg-white/5"
        >
          <span
            class="grid w-14 h-16 rounded-lg text-xs font-bold uppercase place-items-center"
            :style="{ background: docColor(ext) }"
          >
            {{ ext.slice(0, 4) || 'doc' }}
          </span>
          <p class="text-sm leading-relaxed text-white/80">{{ reasonText }}</p>
          <div class="flex flex-wrap justify-center gap-2">
            <button
              v-if="touch && file.kind === 'pdf' && file.viewUrl"
              type="button"
              class="flex items-center gap-2 px-4 h-10 rounded-full text-sm font-medium bg-white text-black"
              @click="openTab"
            >
              <span class="i-lucide-external-link size-4" />
              {{ t('OUTSIDER_WHATSAPP.FILE_VIEWER.OPEN') }}
            </button>
            <a
              v-if="file.editUrl"
              :href="file.editUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 px-4 h-10 rounded-full text-sm font-medium bg-white/10 hover:bg-white/20"
            >
              <span class="i-lucide-pencil size-4" />
              {{ t('OUTSIDER_WHATSAPP.FILE_VIEWER.EDIT') }}
            </a>
            <a
              v-if="file.downloadUrl"
              :href="file.downloadUrl"
              target="_blank"
              rel="noopener noreferrer"
              download
              class="flex items-center gap-2 px-4 h-10 rounded-full text-sm font-medium bg-white/10 hover:bg-white/20"
            >
              <span class="i-lucide-download size-4" />
              {{ t('OUTSIDER_WHATSAPP.FILE_VIEWER.DOWNLOAD') }}
            </a>
          </div>
        </div>
      </main>
    </div>
  </TeleportWithDirection>
</template>

<style scoped>
.file-viewer-btn {
  @apply grid size-10 place-items-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white;
}
</style>
