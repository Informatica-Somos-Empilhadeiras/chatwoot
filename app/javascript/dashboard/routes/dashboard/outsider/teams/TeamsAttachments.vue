<script setup>
// OUTSIDER: anexos de uma mensagem do Teams, sem nada gravado no Chatwoot. Imagens: a imagem vem da Microsoft na hora.
// Arquivos (OneDrive/SharePoint): cartão como o do WhatsApp, com a miniatura da primeira página que a Microsoft gera,
// o nome, o tipo e o botãozinho de baixar. Clicar abre o visualizador do Chatwoot (só para ler); "Editar no Office"
// abre o arquivo no Office/OneDrive. Áudios (inclusive as mensagens de voz do Teams) tocam aqui, no player do WhatsApp,
// com "Transcrever" no navegador (o texto fica no anexo da mensagem, via api/outsider/transcriptions.js).
// Fotos e vídeos: álbum como no WhatsApp (2 lado a lado, 3 com a primeira larga, 4 ou mais em grade com "+N") e
// "Baixar tudo" num .zip. `group` junta várias mensagens seguidas só com fotos/vídeos num álbum só (TeamsChatView).
// Clicar abre o visualizador do WhatsApp com todas as fotos/vídeos do chat, a posição ("3 de 12") e as miniaturas
// embaixo (o chat/canal passa a lista e as ações por provide('teamsMedia'); sem ele, só as desta mensagem).
import { computed, inject, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import TranscriptionsAPI from 'dashboard/api/outsider/transcriptions';
import { formatSize } from 'dashboard/components-next/outsider/mediaViewer/mediaHelpers';
import { docColor } from 'dashboard/helper/outsider/documentFile';
import { openFileViewerWith } from 'dashboard/components-next/outsider/fileViewer/fileViewerStore';
import VoicePlayer from 'dashboard/components-next/message/outsider/VoicePlayer.vue';
import { ORIENTATION } from 'dashboard/components-next/message/constants';
import { useAlert } from 'dashboard/composables';
import MediaViewer from 'dashboard/components-next/outsider/mediaViewer/MediaViewer.vue';
import {
  downloadZip,
  isMedia,
  mediaKey,
  startDownload,
  viewerItem,
} from './teamsMedia';

const props = defineProps({
  message: { type: Object, required: true },
  // várias mensagens seguidas só com fotos/vídeos (álbum); a primeira é `message`
  group: { type: Array, default: null },
});
const { t } = useI18n();
const media = inject('teamsMedia', null);

const ALBUM_TILES = 4;
const broken = reactive({});
const all = computed(() => props.message.attachments || []);
const messages = computed(() => props.group || [props.message]);
// fotos e vídeos (de todas as mensagens do álbum), cada um com a mensagem de onde veio
const album = computed(() =>
  messages.value.flatMap(message =>
    (message.attachments || [])
      .filter(isMedia)
      .map(item => ({ message, item, key: mediaKey(message, item) }))
  )
);
const tiles = computed(() => album.value.slice(0, ALBUM_TILES));
const hidden = computed(() => album.value.length - ALBUM_TILES);
const isAlbum = computed(() => album.value.length > 1);
const tileClass = position => {
  if (album.value.length === 3 && position === 0)
    return 'col-span-2 aspect-[2/1]';
  return 'aspect-square';
};
const albumCount = computed(() => {
  const videos = album.value.filter(
    entry => entry.item.kind === 'video'
  ).length;
  const photos = album.value.length - videos;
  return [
    photos
      ? t('OUTSIDER_TEAMS_AREA.ALBUM.PHOTOS', { count: photos }, photos)
      : '',
    videos
      ? t('OUTSIDER_TEAMS_AREA.ALBUM.VIDEOS', { count: videos }, videos)
      : '',
  ]
    .filter(Boolean)
    .join(' · ');
});

// ---------- visualizador ----------
const viewing = ref(null);
const viewerList = computed(() => {
  const own = album.value.map(entry =>
    viewerItem(entry.message, entry.item, t('OUTSIDER_TEAMS_AREA.YOU'))
  );
  const shared = media?.items?.value || [];
  return shared.length ? [...shared, ...own] : own;
});
const openMedia = entry => {
  viewing.value = viewerItem(
    entry.message,
    entry.item,
    t('OUTSIDER_TEAMS_AREA.YOU')
  );
};
const viewerActions = computed(() => ({
  download: item => startDownload(item.download_url),
  jump: media?.jump ? item => media.jump(item.message_id) : null,
  forward: media?.forward ? item => media.forward(item.message_id) : null,
}));

// ---------- baixar tudo ----------
const zipping = ref(false);
const downloadAll = async () => {
  if (zipping.value) return;
  zipping.value = true;
  try {
    await downloadZip(
      props.message.thread_id,
      album.value.map(entry => ({
        message_id: entry.message.id,
        index: entry.item.index,
      }))
    );
  } catch (error) {
    useAlert(t('OUTSIDER_TEAMS_AREA.ZIP_ERROR'));
  } finally {
    zipping.value = false;
  }
};

const images = computed(() =>
  all.value.filter(item => item.kind === 'image' && !isMedia(item))
);
const audios = computed(() =>
  all.value.filter(item => item.kind === 'audio' && item.audio_url)
);
const files = computed(() =>
  all.value.filter(
    item =>
      item.kind !== 'image' && !audios.value.includes(item) && !isMedia(item)
  )
);
// o player do WhatsApp: { id (para lembrar o que já foi ouvido), dataUrl }
const audioAttachment = item => ({
  id: `teams-${props.message.id}-${item.index}`,
  // o player quer um endereço completo
  dataUrl: new URL(item.audio_url, window.location.origin).href,
  transcribedText: item.transcript || '',
});
// a transcrição lê o arquivo passando pelo Chatwoot (a Microsoft não deixa o navegador ler direto)
const transcribeUrl = item =>
  `${new URL(item.audio_url, window.location.origin).href}&bytes=1`;
const saveTranscript = item => (text, result) =>
  TranscriptionsAPI.saveTeams(props.message.id, item.index, {
    text,
    engine: 'navegador',
    model: result?.model || result?.size || '',
    language: 'pt',
    duration: result?.duration || 0,
  });
const audioSender = computed(() => ({ name: props.message.sender_name }));

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
  <div
    v-if="all.length || album.length"
    class="flex flex-col gap-1.5 mt-1.5 whitespace-normal"
  >
    <!-- fotos e vídeos: álbum (2 ou mais) ou uma só -->
    <div v-if="album.length" class="w-72 max-w-full" data-teams-album>
      <div
        class="grid gap-1 overflow-hidden rounded-lg"
        :class="isAlbum ? 'grid-cols-2' : 'grid-cols-1'"
      >
        <button
          v-for="(entry, position) in tiles"
          :key="entry.key"
          type="button"
          class="relative overflow-hidden rounded-md bg-n-alpha-2"
          :class="isAlbum ? tileClass(position) : 'max-h-72'"
          :title="entry.item.name"
          :data-teams-media="entry.key"
          @click="openMedia(entry)"
        >
          <img
            v-if="!broken[entry.key]"
            :src="entry.item.thumb_url"
            :alt="entry.item.name"
            class="object-cover"
            :class="
              isAlbum ? 'size-full' : 'w-full h-auto max-h-72 min-h-[90px]'
            "
            loading="lazy"
            @error="broken[entry.key] = true"
          />
          <span
            v-else
            class="flex flex-col items-center justify-center gap-1 p-2 text-xs size-full min-h-[90px] text-n-slate-11"
          >
            <span
              :class="
                entry.item.kind === 'video' ? 'i-lucide-film' : 'i-lucide-image'
              "
              class="size-5"
            />
            <span class="w-full truncate">{{ entry.item.name }}</span>
          </span>
          <span
            v-if="entry.item.kind === 'video'"
            class="absolute inset-0 grid m-auto text-white rounded-full size-10 place-items-center bg-black/50"
          >
            <span class="i-lucide-play size-5" />
          </span>
          <span
            v-if="position === ALBUM_TILES - 1 && hidden > 0"
            class="absolute inset-0 grid text-2xl font-semibold text-white place-items-center bg-black/55"
          >
            {{ `+${hidden}` }}
          </span>
        </button>
      </div>
      <div
        class="flex items-center gap-2 mt-1 text-xs text-n-slate-11"
        :class="isAlbum ? '' : 'justify-end'"
      >
        <span v-if="isAlbum" class="flex-1 truncate">{{ albumCount }}</span>
        <button
          v-if="isAlbum"
          type="button"
          class="flex items-center gap-1 px-2 py-1 font-medium rounded-full hover:bg-n-alpha-2 text-n-slate-12 disabled:opacity-60"
          :disabled="zipping"
          data-teams-album-zip
          @click="downloadAll"
        >
          <span
            :class="
              zipping
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-download'
            "
            class="size-3.5"
          />
          {{ t('OUTSIDER_TEAMS_AREA.ALBUM.DOWNLOAD_ALL') }}
        </button>
        <button
          v-else-if="tiles[0]?.item.download_url"
          type="button"
          class="flex items-center gap-1 px-2 py-1 rounded-full hover:bg-n-alpha-2"
          :title="t('OUTSIDER_TEAMS_AREA.FILE_DOWNLOAD')"
          @click="startDownload(tiles[0].item.download_url)"
        >
          <span class="i-lucide-download size-3.5" />
          <span class="max-w-[12rem] truncate">{{ tiles[0].item.name }}</span>
        </button>
      </div>
    </div>
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
      v-for="audio in audios"
      :key="`a-${audio.index}`"
      class="w-72 max-w-full"
      data-teams-audio
    >
      <VoicePlayer
        :attachment="audioAttachment(audio)"
        :sender="audioSender"
        :orientation="message.mine ? ORIENTATION.RIGHT : ORIENTATION.LEFT"
        :transcriber="message.id ? saveTranscript(audio) : null"
        :transcribe-url="transcribeUrl(audio)"
      />
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
    <MediaViewer
      v-if="viewing"
      show
      :attachment="viewing"
      :all-attachments="viewerList"
      :actions="viewerActions"
      @close="viewing = null"
    />
  </div>
</template>
