<script setup>
// OUTSIDER: anexos de uma mensagem do Teams, sem nada gravado no Chatwoot. Imagens: a imagem vem da Microsoft na hora.
// Arquivos (OneDrive/SharePoint): cartão como o do WhatsApp, com a miniatura da primeira página que a Microsoft gera,
// o nome, o tipo e o botãozinho de baixar. Clicar abre o visualizador do Chatwoot (só para ler); "Editar no Office"
// abre o arquivo no Office/OneDrive.
import { computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import { formatSize } from 'dashboard/components-next/outsider/mediaViewer/mediaHelpers';
import { docColor } from 'dashboard/helper/outsider/documentFile';
import { openFileViewerWith } from 'dashboard/components-next/outsider/fileViewer/fileViewerStore';

const props = defineProps({ message: { type: Object, required: true } });
const { t } = useI18n();

const broken = reactive({});
const all = computed(() => props.message.attachments || []);
const images = computed(() => all.value.filter(item => item.kind === 'image'));
const files = computed(() => all.value.filter(item => item.kind !== 'image'));

const meta = file =>
  [String(file.extension || '').toUpperCase(), formatSize(file.size)]
    .filter(Boolean)
    .join(' · ');

const sourceText = file =>
  ({
    onedrive: t('OUTSIDER_TEAMS_AREA.FILE_ONEDRIVE'),
    sharepoint: t('OUTSIDER_TEAMS_AREA.FILE_SHAREPOINT'),
  })[file.source] || '';

const open = item => {
  if (!props.message.id || item.thumb_url === null) return;
  const base = {
    name: item.name,
    extension: item.extension,
    size: item.size,
    kind: item.kind === 'image' ? 'image' : 'none',
    viewUrl: item.kind === 'image' ? item.thumb_url : '',
    downloadUrl: item.download_url,
    editUrl: item.edit_url,
  };
  openFileViewerWith(base, async () => {
    const { data } = await TeamsGraphAPI.preview(
      props.message.thread_id,
      props.message.id,
      item.index
    );
    return {
      kind: data.kind,
      reason: data.reason,
      size: data.size ?? item.size,
      viewUrl: data.view_url,
      downloadUrl: data.download_url || item.download_url,
      editUrl: data.edit_url || item.edit_url,
    };
  });
};
</script>

<template>
  <div v-if="all.length" class="flex flex-col gap-1.5 mt-1.5 whitespace-normal">
    <div v-if="images.length" class="flex flex-wrap gap-1.5">
      <button
        v-for="image in images"
        :key="`i-${image.index}`"
        type="button"
        class="overflow-hidden rounded-lg bg-n-alpha-2"
        :title="image.name"
        @click="open(image)"
      >
        <img
          v-if="image.thumb_url && !broken[image.index]"
          :src="image.thumb_url"
          :alt="image.name"
          class="object-cover max-h-60 max-w-[280px] min-w-[120px] min-h-[80px]"
          loading="lazy"
          @error="broken[image.index] = true"
        />
        <span
          v-else
          class="flex items-center gap-1.5 px-3 py-2 text-xs text-n-slate-11"
        >
          <span class="i-lucide-image size-4" />
          {{ image.name }}
        </span>
      </button>
    </div>
    <div
      v-for="file in files"
      :key="`f-${file.index}`"
      class="w-72 max-w-full overflow-hidden border rounded-xl tms-border bg-n-surface-1"
      data-teams-file
    >
      <button
        v-if="file.thumb_url && !broken[file.index]"
        type="button"
        class="block w-full h-[130px] overflow-hidden bg-white border-b tms-border"
        :title="t('OUTSIDER_TEAMS_AREA.FILE_VIEW', { name: file.name })"
        @click="open(file)"
      >
        <img
          :src="file.thumb_url"
          alt=""
          class="object-cover object-top w-full h-full"
          loading="lazy"
          @error="broken[file.index] = true"
        />
      </button>
      <div class="flex items-center gap-2.5 px-2.5 py-2">
        <button
          type="button"
          class="flex items-center flex-1 min-w-0 gap-2.5 text-start"
          :title="file.name"
          @click="open(file)"
        >
          <span
            class="grid w-8 h-10 rounded-md text-[9px] font-bold text-white uppercase place-items-center shrink-0"
            :style="{ background: docColor(file.extension) }"
          >
            {{ (file.extension || 'doc').slice(0, 4) }}
          </span>
          <span class="flex flex-col min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ file.name }}
            </span>
            <span class="text-xs truncate text-n-slate-11">
              {{ [meta(file), sourceText(file)].filter(Boolean).join(' · ') }}
            </span>
          </span>
        </button>
        <a
          v-if="file.download_url"
          :href="file.download_url"
          target="_blank"
          rel="noopener noreferrer"
          class="grid border rounded-full size-8 place-items-center shrink-0 border-n-slate-7 text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          :title="t('OUTSIDER_TEAMS_AREA.FILE_DOWNLOAD')"
          :aria-label="t('OUTSIDER_TEAMS_AREA.FILE_DOWNLOAD')"
        >
          <span class="i-lucide-download size-4" />
        </a>
      </div>
    </div>
  </div>
</template>
