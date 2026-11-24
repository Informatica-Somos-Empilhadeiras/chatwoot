<script setup>
// OUTSIDER: arquivos dos Aplicativos (OneDrive; Google Drive na próxima entrega). Abas Meus arquivos, Compartilhados
// comigo e Recentes; pastas com o caminho em cima, busca, Nova pasta, Enviar arquivo (botão ou arrastar) e o painel do
// arquivo escolhido com a miniatura e Abrir (visualizador do Chatwoot), Baixar, Copiar link, Abrir no OneDrive e Excluir.
// Espelho: nada fica no Chatwoot; Baixar vai direto da Microsoft para o navegador.
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AppsAPI from 'dashboard/api/outsider/apps';
import { openFileViewerWith } from 'dashboard/components-next/outsider/fileViewer/fileViewerStore';
import { formatSize } from 'dashboard/components-next/outsider/mediaViewer/mediaHelpers';
import AppLogo from '../AppLogo.vue';
import AppsGate from '../AppsGate.vue';
import { providerOf, gateOf, textKey } from '../providers';
import { listTime } from '../../teams/helpers';
import { errorText } from '../appsErrors';
import { fileIcon, canDownload } from './driveHelpers';
import '../apps.css';

const { t } = useI18n();
const route = useRoute();

const VIEWS = ['mine', 'shared', 'recent'];

const providerKey = computed(() => route.params.provider || 'microsoft');
const info = computed(() => providerOf(providerKey.value));
const gate = computed(() =>
  gateOf(providerKey.value, info.value.drive.feature)
);
const appName = computed(() => t(info.value.drive.name));

const view = ref('mine');
// caminho aberto: a raiz da aba e as pastas por onde a pessoa entrou
const path = ref([]);
const items = ref([]);
const next = ref(null);
const isLoading = ref(false);
const isMore = ref(false);
const error = ref('');
const query = ref('');
const searched = ref('');
const selected = ref(null);
const details = ref(null);
const isDetailsLoading = ref(false);
const uploads = ref([]); // { name, progress }
const dragging = ref(false);
const fileInput = ref(null);
const newFolder = ref(null); // nome sendo digitado

const folder = computed(() => path.value[path.value.length - 1] || null);
const canWrite = computed(
  () => !searched.value && (view.value === 'mine' || !!folder.value)
);

let ticket = 0;
const load = async () => {
  if (gate.value !== 'ready') return;
  ticket += 1;
  const mine = ticket;
  isLoading.value = true;
  error.value = '';
  try {
    const { data } = await AppsAPI.driveItems(providerKey.value, {
      view: view.value,
      drive_id: folder.value?.drive_id || undefined,
      folder_id: folder.value?.id || undefined,
      q: searched.value || undefined,
    });
    if (mine !== ticket) return;
    items.value = data.items || [];
    next.value = data.next || null;
  } catch (e) {
    if (mine === ticket) error.value = errorText(e, t);
  } finally {
    if (mine === ticket) isLoading.value = false;
  }
};

const loadMore = async () => {
  if (!next.value || isMore.value) return;
  isMore.value = true;
  try {
    const { data } = await AppsAPI.driveItems(providerKey.value, {
      cursor: next.value,
    });
    items.value = [...items.value, ...(data.items || [])];
    next.value = data.next || null;
  } catch (e) {
    useAlert(errorText(e, t));
  } finally {
    isMore.value = false;
  }
};

const onScroll = event => {
  const el = event.target;
  if (el.scrollTop + el.clientHeight > el.scrollHeight - 160) loadMore();
};

const setView = value => {
  view.value = value;
  path.value = [];
  searched.value = '';
  query.value = '';
  selected.value = null;
  load();
};

const goTo = index => {
  path.value = path.value.slice(0, index);
  selected.value = null;
  load();
};

const select = async item => {
  if (item.folder) {
    path.value = [...path.value, item];
    selected.value = null;
    searched.value = '';
    query.value = '';
    load();
    return;
  }
  selected.value = item;
  details.value = null;
  isDetailsLoading.value = true;
  try {
    const { data } = await AppsAPI.driveItem(providerKey.value, item);
    if (selected.value === item) details.value = data;
  } catch {
    if (selected.value === item) details.value = { ...item };
  } finally {
    isDetailsLoading.value = false;
  }
};

const search = () => {
  searched.value = query.value.trim();
  selected.value = null;
  load();
};
const clearSearch = () => {
  query.value = '';
  if (searched.value) search();
};

const open = item => {
  // Documento do Google não tem extensão no nome
  const name = String(item.name);
  const ext = name.includes('.') ? name.split('.').pop().toLowerCase() : '';
  const editLabel = info.value.texts['DRIVE.EDIT']
    ? t(info.value.texts['DRIVE.EDIT'])
    : '';
  openFileViewerWith(
    {
      name: item.name,
      extension: ext,
      size: item.size,
      editUrl: item.web_url,
      editLabel,
    },
    async () => {
      const { data } = await AppsAPI.drivePreview(providerKey.value, item);
      return {
        kind: data.kind,
        reason: data.reason,
        viewUrl: data.view_url,
        downloadUrl: data.download_url,
        editUrl: data.edit_url || item.web_url,
      };
    }
  );
};

const download = async item => {
  try {
    const { data } = await AppsAPI.driveDownload(providerKey.value, item);
    const link = document.createElement('a');
    link.href = data.url;
    link.rel = 'noopener';
    link.click();
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

const copyLink = async item => {
  try {
    const { data } = await AppsAPI.driveShare(providerKey.value, item);
    await navigator.clipboard.writeText(data.url);
    useAlert(t('OUTSIDER_APPS.DRIVE.LINK_COPIED'));
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

const remove = async item => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t(textKey(providerKey.value, 'DRIVE.CONFIRM_DELETE'), { name: item.name })
    )
  )
    return;
  try {
    await AppsAPI.driveDelete(providerKey.value, item);
    items.value = items.value.filter(other => other.id !== item.id);
    if (selected.value?.id === item.id) selected.value = null;
    useAlert(t('OUTSIDER_APPS.DRIVE.DELETED'));
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

const createFolder = async () => {
  const name = (newFolder.value || '').trim();
  if (!name) return;
  try {
    const { data } = await AppsAPI.driveFolder(providerKey.value, {
      driveId: folder.value?.drive_id,
      parentId: folder.value?.id,
      name,
    });
    newFolder.value = null;
    items.value = [data, ...items.value];
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

const upload = async fileList => {
  if (!canWrite.value) return;
  const target = folder.value;
  await Array.from(fileList || []).reduce(async (previous, file) => {
    await previous;
    const entry = { name: file.name, progress: 0 };
    uploads.value.push(entry);
    try {
      const { data } = await AppsAPI.driveUpload(
        providerKey.value,
        { driveId: target?.drive_id, parentId: target?.id, file },
        event => {
          entry.progress = event.total
            ? Math.round((event.loaded / event.total) * 100)
            : 0;
        }
      );
      if (folder.value === target) items.value = [...items.value, data];
    } catch (e) {
      useAlert(`${file.name}: ${errorText(e, t)}`);
    } finally {
      uploads.value = uploads.value.filter(item => item !== entry);
    }
  }, Promise.resolve());
};

const onDrop = event => {
  dragging.value = false;
  upload(event.dataTransfer?.files);
};

watch(gate, value => value === 'ready' && load());
onMounted(load);
</script>

<template>
  <section
    class="relative flex w-full h-full overflow-hidden oapps bg-n-surface-1"
    data-apps-drive
    @dragover.prevent="canWrite && (dragging = true)"
    @dragleave.self="dragging = false"
    @drop.prevent="onDrop"
  >
    <AppsGate
      v-if="gate !== 'ready'"
      :provider="providerKey"
      :state="gate"
      :logo="info.drive.logo"
      :app-name="appName"
    />
    <template v-else>
      <div class="flex flex-col flex-1 min-w-0">
        <header
          class="flex flex-wrap items-center gap-2 px-4 py-3 border-b border-n-weak md:px-5"
        >
          <AppLogo :name="info.drive.logo" :size="30" />
          <h2 class="mb-0 mr-2 text-lg font-semibold text-n-slate-12">
            {{ appName }}
          </h2>
          <span class="oa-tabs">
            <button
              v-for="option in VIEWS"
              :key="option"
              type="button"
              :class="{ on: view === option }"
              :data-apps-drive-view="option"
              @click="setView(option)"
            >
              {{ t(`OUTSIDER_APPS.DRIVE.VIEW_${option.toUpperCase()}`) }}
            </button>
          </span>
          <span class="flex-1" />
          <button
            type="button"
            class="oa-ghost"
            :disabled="!canWrite"
            :title="t('OUTSIDER_APPS.DRIVE.NEW_FOLDER')"
            data-apps-drive-new-folder
            @click="newFolder = ''"
          >
            <Icon icon="i-lucide-folder-plus" class="size-4" />
            <span :class="selected ? 'hidden 2xl:inline' : 'hidden sm:inline'">
              {{ t('OUTSIDER_APPS.DRIVE.NEW_FOLDER') }}
            </span>
          </button>
          <button
            type="button"
            class="oa-btn"
            :disabled="!canWrite"
            :title="t('OUTSIDER_APPS.DRIVE.UPLOAD')"
            data-apps-drive-upload
            @click="fileInput?.click()"
          >
            <Icon icon="i-lucide-upload" class="size-4" />
            <span :class="selected ? 'hidden 2xl:inline' : 'hidden sm:inline'">
              {{ t('OUTSIDER_APPS.DRIVE.UPLOAD') }}
            </span>
          </button>
          <input
            ref="fileInput"
            type="file"
            multiple
            class="hidden"
            @change="
              upload($event.target.files);
              $event.target.value = '';
            "
          />
        </header>

        <div class="flex flex-wrap items-center gap-2 px-4 py-2.5 md:px-5">
          <nav
            class="flex flex-wrap items-center flex-1 min-w-0 gap-1 text-sm text-n-slate-11"
            data-apps-drive-path
          >
            <button type="button" class="hover:underline" @click="goTo(0)">
              {{ t(`OUTSIDER_APPS.DRIVE.VIEW_${view.toUpperCase()}`) }}
            </button>
            <template v-for="(step, index) in path" :key="step.id">
              <Icon icon="i-lucide-chevron-right" class="size-3.5" />
              <button
                type="button"
                class="max-w-[180px] truncate"
                :class="
                  index === path.length - 1
                    ? 'font-semibold text-n-slate-12'
                    : 'hover:underline'
                "
                @click="goTo(index + 1)"
              >
                {{ step.name }}
              </button>
            </template>
            <template v-if="searched">
              <Icon icon="i-lucide-chevron-right" class="size-3.5" />
              <span class="font-semibold text-n-slate-12">
                {{ `“${searched}”` }}
              </span>
            </template>
          </nav>
          <form
            class="flex items-center w-full gap-2 px-3 py-2 sm:w-72 rounded-xl bg-n-alpha-2 text-n-slate-10"
            @submit.prevent="search"
          >
            <Icon icon="i-lucide-search" class="size-4 shrink-0" />
            <input
              v-model="query"
              type="text"
              class="reset-base !m-0 !p-0 !border-0 !bg-transparent !h-auto !shadow-none text-sm text-n-slate-12 w-full outline-none"
              :placeholder="t('OUTSIDER_APPS.DRIVE.SEARCH', { app: appName })"
              data-apps-drive-search
            />
            <button v-if="query" type="button" @click="clearSearch">
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </form>
        </div>

        <div class="flex-1 min-h-0 overflow-y-auto" @scroll.passive="onScroll">
          <form
            v-if="newFolder !== null"
            class="flex items-center gap-2 px-4 py-2 mx-4 mb-2 border rounded-xl border-n-weak md:mx-5"
            @submit.prevent="createFolder"
          >
            <Icon icon="i-lucide-folder" class="size-5 text-n-amber-10" />
            <input
              v-model="newFolder"
              type="text"
              class="!m-0 flex-1 text-sm"
              :placeholder="t('OUTSIDER_APPS.DRIVE.FOLDER_NAME')"
              maxlength="200"
              data-apps-drive-folder-name
            />
            <button type="submit" class="oa-btn !h-8">
              {{ t('OUTSIDER_APPS.DRIVE.CREATE') }}
            </button>
            <button
              type="button"
              class="oa-ghost !h-8"
              @click="newFolder = null"
            >
              {{ t('OUTSIDER_APPS.CLOSE') }}
            </button>
          </form>

          <div
            v-for="item in uploads"
            :key="item.name"
            class="flex items-center gap-3 px-4 py-2 mx-4 text-sm md:mx-5 text-n-slate-11"
          >
            <Spinner :size="14" />
            <span class="flex-1 truncate">{{ item.name }}</span>
            <span>{{ item.progress }}%</span>
          </div>

          <div v-if="isLoading" class="flex justify-center py-10">
            <Spinner :size="20" />
          </div>
          <p
            v-else-if="error"
            class="px-4 py-8 text-sm text-center text-n-ruby-11"
          >
            {{ error }}
          </p>
          <p
            v-else-if="!items.length"
            class="px-4 py-10 text-sm text-center text-n-slate-10"
          >
            {{
              searched
                ? t('OUTSIDER_APPS.DRIVE.NO_RESULTS')
                : t('OUTSIDER_APPS.DRIVE.EMPTY')
            }}
          </p>
          <table v-else class="w-full text-sm table-fixed" data-apps-drive-list>
            <thead>
              <tr
                class="text-xs text-left border-b text-n-slate-11 border-n-weak"
              >
                <th class="px-4 py-2 font-semibold md:px-5">
                  {{ t('OUTSIDER_APPS.DRIVE.NAME') }}
                </th>
                <th class="hidden w-24 px-2 py-2 font-semibold md:table-cell">
                  {{ t('OUTSIDER_APPS.DRIVE.SIZE') }}
                </th>
                <th class="hidden px-2 py-2 font-semibold w-44 lg:table-cell">
                  {{ t('OUTSIDER_APPS.DRIVE.MODIFIED_BY') }}
                </th>
                <th class="w-20 px-2 py-2 font-semibold">
                  {{ t('OUTSIDER_APPS.DRIVE.DATE') }}
                </th>
                <th class="w-24 px-2 py-2" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in items"
                :key="`${item.drive_id}-${item.id}`"
                class="border-b cursor-pointer select-none border-n-weak/60 group"
                :class="
                  selected?.id === item.id ? 'oa-sel' : 'hover:bg-n-alpha-1'
                "
                data-apps-drive-item
                @click="select(item)"
                @dblclick="!item.folder && open(item)"
              >
                <td class="px-4 py-2.5 md:px-5">
                  <span class="flex items-center min-w-0 gap-2.5">
                    <Icon
                      :icon="fileIcon(item).icon"
                      class="size-5 shrink-0"
                      :class="fileIcon(item).tone"
                    />
                    <span class="truncate text-n-slate-12">{{
                      item.name
                    }}</span>
                  </span>
                </td>
                <td class="hidden px-2 py-2.5 md:table-cell text-n-slate-11">
                  {{
                    item.folder
                      ? item.child_count != null
                        ? t('OUTSIDER_APPS.DRIVE.ITEMS', {
                            count: item.child_count,
                          })
                        : '—'
                      : item.size != null
                        ? formatSize(item.size)
                        : '—'
                  }}
                </td>
                <td
                  class="hidden px-2 py-2.5 truncate lg:table-cell text-n-slate-11"
                >
                  {{ item.modified_by || '—' }}
                </td>
                <td class="px-2 py-2.5 text-n-slate-11">
                  {{ listTime(item.modified_at, t) }}
                </td>
                <td class="px-2 py-0">
                  <span
                    v-if="!item.folder"
                    class="flex justify-end gap-1 opacity-60 group-hover:opacity-100"
                  >
                    <button
                      v-if="canDownload(item)"
                      type="button"
                      class="grid rounded size-7 !p-0 place-items-center hover:bg-n-alpha-2"
                      :title="t('OUTSIDER_APPS.DOWNLOAD')"
                      @click.stop="download(item)"
                    >
                      <Icon icon="i-lucide-download" class="size-4" />
                    </button>
                    <button
                      type="button"
                      class="grid rounded size-7 !p-0 place-items-center hover:bg-n-alpha-2"
                      :title="t('OUTSIDER_APPS.DRIVE.COPY_LINK')"
                      @click.stop="copyLink(item)"
                    >
                      <Icon icon="i-lucide-link" class="size-4" />
                    </button>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
          <div class="flex justify-center py-3">
            <Spinner v-if="isMore" :size="16" />
            <button
              v-else-if="next"
              type="button"
              class="text-xs text-n-slate-11 hover:underline"
              @click="loadMore"
            >
              {{ t('OUTSIDER_APPS.MAIL.MORE') }}
            </button>
          </div>
          <div
            v-if="canWrite && !isLoading"
            class="mx-4 mb-4 p-4 text-sm text-center border-2 border-dashed md:mx-5 rounded-xl border-n-weak text-n-slate-10"
          >
            {{ t('OUTSIDER_APPS.DRIVE.DROP_HINT') }}
          </div>
        </div>
      </div>

      <!-- ===== arquivo escolhido ===== -->
      <aside
        v-if="selected"
        class="absolute inset-0 z-20 flex flex-col gap-3 p-4 overflow-y-auto border-l md:static md:w-[340px] shrink-0 border-n-weak bg-n-surface-1"
        data-apps-drive-details
      >
        <div class="flex items-start gap-2">
          <b class="flex-1 min-w-0 text-sm break-words text-n-slate-12">{{
            selected.name
          }}</b>
          <button
            type="button"
            class="text-n-slate-11"
            :aria-label="t('OUTSIDER_APPS.CLOSE')"
            @click="selected = null"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>
        <button
          type="button"
          class="grid overflow-hidden border h-60 place-items-center rounded-xl border-n-weak bg-n-alpha-1"
          @click="open(selected)"
        >
          <Spinner v-if="isDetailsLoading" :size="18" />
          <img
            v-else-if="details?.thumbnail"
            :src="details.thumbnail"
            alt=""
            class="object-contain w-full h-full"
            referrerpolicy="no-referrer"
          />
          <Icon
            v-else
            :icon="fileIcon(selected).icon"
            class="size-14"
            :class="fileIcon(selected).tone"
          />
        </button>
        <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 text-xs mb-0">
          <template v-if="selected.size != null">
            <dt class="text-n-slate-11">
              {{ t('OUTSIDER_APPS.DRIVE.SIZE') }}
            </dt>
            <dd class="mb-0 text-right text-n-slate-12">
              {{ formatSize(selected.size) }}
            </dd>
          </template>
          <dt class="text-n-slate-11">
            {{ t('OUTSIDER_APPS.DRIVE.MODIFIED_BY') }}
          </dt>
          <dd class="mb-0 text-right truncate text-n-slate-12">
            {{ selected.modified_by || '—' }}
          </dd>
          <dt class="text-n-slate-11">{{ t('OUTSIDER_APPS.DRIVE.DATE') }}</dt>
          <dd class="mb-0 text-right text-n-slate-12">
            {{
              selected.modified_at
                ? new Date(selected.modified_at).toLocaleString('pt-BR')
                : '—'
            }}
          </dd>
        </dl>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            class="oa-btn"
            data-apps-drive-open
            @click="open(selected)"
          >
            <Icon icon="i-lucide-eye" class="size-4" />
            {{ t('OUTSIDER_APPS.DRIVE.OPEN') }}
          </button>
          <button
            v-if="canDownload(selected)"
            type="button"
            class="oa-ghost"
            @click="download(selected)"
          >
            <Icon icon="i-lucide-download" class="size-4" />
            {{ t('OUTSIDER_APPS.DOWNLOAD') }}
          </button>
          <button type="button" class="oa-ghost" @click="copyLink(selected)">
            <Icon icon="i-lucide-link" class="size-4" />
            {{ t('OUTSIDER_APPS.DRIVE.COPY_LINK') }}
          </button>
          <a
            v-if="selected.web_url"
            :href="selected.web_url"
            target="_blank"
            rel="noopener noreferrer"
            class="oa-ghost"
          >
            <Icon icon="i-lucide-external-link" class="size-4" />
            {{ t('OUTSIDER_APPS.DRIVE.OPEN_WEB', { app: appName }) }}
          </a>
          <button
            type="button"
            class="oa-ghost is-danger"
            @click="remove(selected)"
          >
            <Icon icon="i-lucide-trash-2" class="size-4" />
            {{ t('OUTSIDER_APPS.DRIVE.DELETE') }}
          </button>
        </div>
        <p class="mt-auto mb-0 text-[11px] text-n-slate-10">
          {{ t('OUTSIDER_APPS.MIRROR_NOTE') }}
        </p>
      </aside>

      <div
        v-if="dragging"
        class="absolute inset-0 z-30 grid m-3 text-sm border-2 border-dashed pointer-events-none place-items-center rounded-2xl bg-n-surface-1/90 border-[var(--oa-accent)] text-n-slate-12"
      >
        {{
          t('OUTSIDER_APPS.DRIVE.DROP', {
            folder:
              folder?.name ||
              t(`OUTSIDER_APPS.DRIVE.VIEW_${view.toUpperCase()}`),
          })
        }}
      </div>
    </template>
  </section>
</template>
