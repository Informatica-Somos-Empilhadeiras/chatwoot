<script setup>
// OUTSIDER: e-mail dos Aplicativos (Outlook; Gmail na próxima entrega). Três colunas: pastas, lista (25 por vez, com
// busca e os filtros Não lidos, Com anexo e Sinalizados) e o e-mail aberto. No celular aparece uma coisa de cada vez.
// Espelho: a lista e o e-mail vêm da conta da pessoa na hora; o Chatwoot não guarda nada. E-mail novo chega pelo aviso
// ao vivo (outsider.notice, kind 'apps') e entra no topo da Caixa de entrada.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AppsAPI from 'dashboard/api/outsider/apps';
import AppLogo from '../AppLogo.vue';
import AppsGate from '../AppsGate.vue';
import MailReader from './MailReader.vue';
import MailComposer from './MailComposer.vue';
import { providerOf, gateOf, textKey } from '../providers';
import {
  appsState,
  setUnreadMail,
  APPS_NOTICE,
  MAIL_ROUTE,
} from '../appsStore';
import { listTime } from '../../teams/helpers';
import { errorText } from '../appsErrors';
import { initialsOf, avatarTone } from './mailHelpers';
import '../apps.css';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const FOLDER_ICONS = {
  inbox: 'i-lucide-inbox',
  drafts: 'i-lucide-file-pen-line',
  sentitems: 'i-lucide-send',
  deleteditems: 'i-lucide-trash-2',
  archive: 'i-lucide-archive',
  junkemail: 'i-lucide-shield-alert',
  custom: 'i-lucide-folder',
  // Gmail: as abas da Caixa de entrada e os marcadores da pessoa
  promotions: 'i-lucide-tag',
  social: 'i-lucide-users',
  updates: 'i-lucide-info',
  forums: 'i-lucide-messages-square',
  label: 'i-lucide-bookmark',
};
const FILTERS = ['all', 'unread', 'attachments', 'flagged'];

const providerKey = computed(() => route.params.provider || 'microsoft');
const info = computed(() => providerOf(providerKey.value));
const gate = computed(() => gateOf(providerKey.value, info.value.mail.feature));
const appName = computed(() => t(info.value.mail.name));

const folders = ref([]);
const items = ref([]);
const next = ref(null);
const isLoading = ref(false);
const isMore = ref(false);
const listError = ref('');
const filter = ref('all');
const query = ref('');
const searched = ref('');
const composer = ref(null); // { mode, source }

const folderId = computed(() => route.query.folder || '');
const messageId = computed(() => route.query.message || '');
const currentFolder = computed(
  () =>
    folders.value.find(folder => folder.id === folderId.value) ||
    folders.value.find(folder => folder.kind === 'inbox') ||
    null
);
const isInbox = computed(() => currentFolder.value?.kind === 'inbox');
const showFolders = ref(false);

const go = queryChanges =>
  router.push({
    name: MAIL_ROUTE,
    params: route.params,
    query: { ...route.query, ...queryChanges },
  });

const openFolder = folder => {
  showFolders.value = false;
  go({ folder: folder.id, message: undefined });
};
const openMessage = item => {
  if (item.unread) {
    item.unread = false;
    if (isInbox.value)
      setUnreadMail(
        providerKey.value,
        appsState[providerKey.value].unreadMail - 1
      );
    if (currentFolder.value)
      currentFolder.value.unread = Math.max(currentFolder.value.unread - 1, 0);
  }
  go({ message: item.id });
};
const closeMessage = () => go({ message: undefined });

const loadFolders = async () => {
  try {
    const { data } = await AppsAPI.mailFolders(providerKey.value);
    folders.value = data.payload || [];
  } catch (error) {
    listError.value = errorText(error, t);
  }
};

let ticket = 0;
const loadList = async () => {
  if (gate.value !== 'ready') return;
  ticket += 1;
  const mine = ticket;
  isLoading.value = true;
  listError.value = '';
  try {
    const { data } = await AppsAPI.mailMessages(providerKey.value, {
      folder: currentFolder.value?.id || folderId.value || 'inbox',
      filter: filter.value === 'all' ? undefined : filter.value,
      q: searched.value || undefined,
    });
    if (mine !== ticket) return;
    items.value = data.items || [];
    next.value = data.next || null;
  } catch (error) {
    if (mine === ticket) listError.value = errorText(error, t);
  } finally {
    if (mine === ticket) isLoading.value = false;
  }
};

const loadMore = async () => {
  if (!next.value || isMore.value) return;
  isMore.value = true;
  try {
    const { data } = await AppsAPI.mailMessages(providerKey.value, {
      cursor: next.value,
    });
    const known = new Set(items.value.map(item => item.id));
    items.value = [
      ...items.value,
      ...(data.items || []).filter(item => !known.has(item.id)),
    ];
    next.value = data.next || null;
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    isMore.value = false;
  }
};

const onScroll = event => {
  const el = event.target;
  if (el.scrollTop + el.clientHeight > el.scrollHeight - 160) loadMore();
};

const search = () => {
  searched.value = query.value.trim();
  loadList();
};
const clearSearch = () => {
  query.value = '';
  if (searched.value) search();
};

// o e-mail aberto mudou (lido, sinalizado, movido): a lista acompanha
const onChanged = ({ id, changes, removed }) => {
  const index = items.value.findIndex(item => item.id === id);
  if (index < 0) return;
  if (removed) {
    items.value.splice(index, 1);
    closeMessage();
    return;
  }
  Object.assign(items.value[index], changes);
};

const reply = (mode, message) => {
  composer.value = { mode, source: message };
};
const onSent = () => {
  composer.value = null;
  useAlert(t('OUTSIDER_APPS.MAIL.SENT'));
  if (currentFolder.value?.kind === 'sentitems') loadList();
};

// e-mail novo chegou (aviso ao vivo): entra no topo da Caixa de entrada aberta
const onNotice = data => {
  if (data?.kind !== 'apps' || data.app !== 'mail') return;
  if (data.provider !== providerKey.value || !data.item) return;
  const inbox = folders.value.find(folder => folder.kind === 'inbox');
  if (inbox && Number.isFinite(data.unread)) inbox.unread = data.unread;
  if (!isInbox.value || searched.value || filter.value === 'flagged') return;
  if (items.value.some(item => item.id === data.item.id)) return;
  items.value = [data.item, ...items.value];
};

watch([folderId, filter], loadList);
watch(gate, async value => {
  if (value !== 'ready') return;
  await loadFolders();
  loadList();
});

onMounted(async () => {
  emitter.on(APPS_NOTICE, onNotice);
  if (gate.value !== 'ready') return;
  await loadFolders();
  loadList();
});
onBeforeUnmount(() => emitter.off(APPS_NOTICE, onNotice));
</script>

<template>
  <section
    class="relative flex w-full h-full overflow-hidden oapps bg-n-surface-1"
    data-apps-mail
  >
    <AppsGate
      v-if="gate !== 'ready'"
      :provider="providerKey"
      :state="gate"
      :logo="info.mail.logo"
      :app-name="appName"
    />
    <template v-else>
      <!-- ===== pastas ===== -->
      <aside
        class="flex-col w-[230px] shrink-0 border-r border-n-weak"
        :class="
          showFolders
            ? 'flex absolute inset-0 z-30 w-full bg-n-surface-1 md:static md:w-[230px]'
            : 'hidden lg:flex'
        "
        data-apps-mail-folders
      >
        <div class="flex items-center gap-2 px-4 pt-4 pb-3">
          <AppLogo :name="info.mail.logo" :size="28" />
          <h2 class="mb-0 text-lg font-semibold text-n-slate-12">
            {{ appName }}
          </h2>
          <button
            type="button"
            class="ml-auto lg:hidden text-n-slate-11"
            @click="showFolders = false"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>
        <div class="px-3 pb-2">
          <button
            type="button"
            class="justify-center w-full oa-btn"
            data-apps-mail-new
            @click="reply('new', null)"
          >
            <Icon icon="i-lucide-pen-line" class="size-4" />
            {{ t('OUTSIDER_APPS.MAIL.NEW') }}
          </button>
        </div>
        <p class="px-4 mb-2 text-[11px] truncate text-n-slate-10">
          {{ appsState[providerKey].email }}
        </p>
        <nav class="flex-1 min-h-0 px-2 pb-3 overflow-y-auto">
          <button
            v-for="folder in folders"
            :key="folder.id"
            type="button"
            class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left rounded-lg"
            :class="
              currentFolder?.id === folder.id
                ? 'oa-soft font-semibold'
                : 'text-n-slate-12 hover:bg-n-alpha-1'
            "
            :data-apps-mail-folder="folder.kind"
            @click="openFolder(folder)"
          >
            <Icon
              :icon="FOLDER_ICONS[folder.kind] || FOLDER_ICONS.custom"
              class="size-4 shrink-0"
            />
            <span class="flex-1 min-w-0 truncate">{{ folder.name }}</span>
            <span v-if="folder.unread" class="text-xs font-semibold">{{
              folder.unread
            }}</span>
          </button>
        </nav>
      </aside>

      <!-- ===== lista ===== -->
      <div
        class="flex-col w-full md:w-[380px] shrink-0 border-r border-n-weak min-w-0"
        :class="messageId ? 'hidden md:flex' : 'flex'"
        data-apps-mail-list
      >
        <div class="flex items-center gap-2 px-3 pt-3">
          <button
            type="button"
            class="oa-ghost lg:!hidden"
            :aria-label="t('OUTSIDER_APPS.MAIL.FOLDERS')"
            @click="showFolders = true"
          >
            <Icon icon="i-lucide-panel-left" class="size-4" />
            <span class="max-w-[120px] truncate">{{
              currentFolder?.name
            }}</span>
          </button>
          <form
            class="flex items-center flex-1 min-w-0 gap-2 px-3 py-2 rounded-xl bg-n-alpha-2 text-n-slate-10"
            @submit.prevent="search"
          >
            <Icon icon="i-lucide-search" class="size-4 shrink-0" />
            <input
              v-model="query"
              type="text"
              class="reset-base !m-0 !p-0 !border-0 !bg-transparent !h-auto !shadow-none text-sm text-n-slate-12 w-full outline-none"
              :placeholder="t('OUTSIDER_APPS.MAIL.SEARCH')"
              data-apps-mail-search
            />
            <button v-if="query" type="button" @click="clearSearch">
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </form>
          <button
            type="button"
            class="oa-btn !px-2.5 md:!hidden"
            :aria-label="t('OUTSIDER_APPS.MAIL.NEW')"
            @click="reply('new', null)"
          >
            <Icon icon="i-lucide-pen-line" class="size-4" />
          </button>
        </div>
        <div class="flex gap-1.5 px-3 py-2 overflow-x-auto">
          <button
            v-for="option in FILTERS"
            :key="option"
            type="button"
            class="px-2.5 py-1 text-xs rounded-full whitespace-nowrap"
            :class="
              filter === option
                ? 'oa-soft font-semibold'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
            :disabled="!!searched"
            @click="filter = option"
          >
            {{ t(textKey(providerKey, `MAIL.FILTER_${option.toUpperCase()}`)) }}
          </button>
        </div>
        <div class="flex-1 min-h-0 overflow-y-auto" @scroll.passive="onScroll">
          <div v-if="isLoading" class="flex justify-center py-8">
            <Spinner :size="20" />
          </div>
          <p
            v-else-if="listError"
            class="px-4 py-6 text-sm text-center text-n-ruby-11"
          >
            {{ listError }}
          </p>
          <p
            v-else-if="!items.length"
            class="px-4 py-10 text-sm text-center text-n-slate-10"
          >
            {{
              searched
                ? t('OUTSIDER_APPS.MAIL.NO_RESULTS')
                : t('OUTSIDER_APPS.MAIL.EMPTY')
            }}
          </p>
          <template v-else>
            <button
              v-for="item in items"
              :key="item.id"
              type="button"
              class="flex w-full gap-3 px-4 py-3 text-left border-b border-n-weak/60"
              :class="messageId === item.id ? 'oa-sel' : 'hover:bg-n-alpha-1'"
              data-apps-mail-item
              @click="openMessage(item)"
            >
              <span
                class="grid text-xs font-semibold rounded-full size-9 place-items-center shrink-0"
                :class="avatarTone(item.from?.email || item.from?.name)"
              >
                {{ initialsOf(item.from?.name || item.from?.email) }}
              </span>
              <span class="flex-1 min-w-0">
                <span class="flex items-center gap-1.5">
                  <span v-if="item.unread" class="oa-dot shrink-0" />
                  <span
                    class="flex-1 min-w-0 text-sm truncate text-n-slate-12"
                    :class="{ 'font-semibold': item.unread }"
                  >
                    {{ item.draft ? t('OUTSIDER_APPS.MAIL.DRAFT') : ''
                    }}{{
                      item.from?.name ||
                      item.from?.email ||
                      t('OUTSIDER_APPS.MAIL.NO_SENDER')
                    }}
                  </span>
                  <span class="text-[11px] text-n-slate-10 shrink-0">{{
                    listTime(item.date, t)
                  }}</span>
                </span>
                <span
                  class="flex items-center gap-1 text-[13px] text-n-slate-12"
                >
                  <span
                    class="flex-1 min-w-0 truncate"
                    :class="{ 'font-semibold': item.unread }"
                  >
                    {{ item.subject || t('OUTSIDER_APPS.MAIL.NO_SUBJECT') }}
                  </span>
                  <Icon
                    v-if="item.has_attachments"
                    icon="i-lucide-paperclip"
                    class="size-3.5 text-n-slate-10 shrink-0"
                  />
                  <Icon
                    v-if="item.flagged"
                    :icon="info.mail.flagIcon || 'i-lucide-flag'"
                    class="size-3.5 shrink-0"
                    :class="
                      info.mail.flagIcon ? 'text-n-amber-10' : 'text-n-ruby-10'
                    "
                  />
                </span>
                <span class="block text-xs truncate text-n-slate-10">{{
                  item.preview
                }}</span>
              </span>
            </button>
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
          </template>
        </div>
      </div>

      <!-- ===== e-mail aberto ===== -->
      <div
        class="flex-1 min-w-0"
        :class="messageId ? 'flex' : 'hidden md:flex'"
      >
        <MailReader
          v-if="messageId"
          :key="messageId"
          :provider="providerKey"
          :message-id="messageId"
          :folders="folders"
          @back="closeMessage"
          @changed="onChanged"
          @reply="reply"
        />
        <div
          v-else
          class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
        >
          <AppLogo :name="info.mail.logo" :size="44" />
          <p class="mb-0 text-sm">{{ t('OUTSIDER_APPS.MAIL.PICK') }}</p>
          <p class="max-w-xs mb-0 text-xs text-center">
            {{ t('OUTSIDER_APPS.MIRROR_NOTE') }}
          </p>
        </div>
      </div>
    </template>

    <MailComposer
      v-if="composer"
      :provider="providerKey"
      :mode="composer.mode"
      :source="composer.source"
      @close="composer = null"
      @sent="onSent"
    />
  </section>
</template>
