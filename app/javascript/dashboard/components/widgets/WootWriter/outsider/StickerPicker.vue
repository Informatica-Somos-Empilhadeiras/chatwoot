<script setup>
// OUTSIDER: figurinhas na caixa de resposta (só WhatsApp: Evolution ou API oficial). O botão ao lado do
// clipe abre o painel com Recentes, Favoritas, Todas e os grupos da pessoa; clicar numa figurinha envia na
// conversa. "+" sobe imagens (viram figurinha 512x512 no servidor, no grupo que estiver aberto); o "⋯" de
// cada figurinha favorita, move de grupo ou apaga; o grupo aberto pode ser renomeado ou apagado.
// A coleção é por atendente (app/services/outsider/sticker_library.rb).
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside, onKeyStroke } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StickersAPI from 'dashboard/api/outsider/stickers';
import {
  stickerState,
  loadStickers,
  putSticker,
  dropSticker,
  markUsed,
  putPack,
  dropPack,
  stickerErrorText,
} from './stickerStore';

const props = defineProps({
  conversationId: { type: Number, default: null },
});

const RECENT_LIMIT = 32;
const FIXED_TABS = ['recent', 'favorites', 'all'];

const { t } = useI18n();
const store = useStore();

const rootRef = ref(null);
const fileInput = ref(null);
const packInput = ref(null);
const isOpen = ref(false);
const tab = ref('all');
const menuFor = ref(null); // id da figurinha com o menu aberto
const moving = ref(false);
const confirmDelete = ref(null);
const sendingId = ref(null);
const uploading = ref(0);
const newPackOpen = ref(false);
const newPackName = ref('');
const renaming = ref(false);
const renameValue = ref('');
const confirmPackDelete = ref(false);

const accountId = computed(() => store.getters.getCurrentAccountId);
const stickers = computed(() => stickerState.stickers);
const packs = computed(() => stickerState.packs);
const recent = computed(() =>
  stickers.value
    .filter(sticker => sticker.last_used_at)
    .sort((a, b) => (a.last_used_at < b.last_used_at ? 1 : -1))
    .slice(0, RECENT_LIMIT)
);
const favorites = computed(() => stickers.value.filter(s => s.favorite));
const activePack = computed(
  () => packs.value.find(pack => pack.id === tab.value) || null
);
const visible = computed(() => {
  if (tab.value === 'recent') return recent.value;
  if (tab.value === 'favorites') return favorites.value;
  if (tab.value === 'all') return stickers.value;
  return stickers.value.filter(sticker => sticker.pack_id === tab.value);
});
const emptyKey = computed(() =>
  FIXED_TABS.includes(tab.value) ? tab.value.toUpperCase() : 'PACK'
);
const tabs = computed(() => [
  {
    key: 'recent',
    label: t('OUTSIDER_WHATSAPP.STICKERS.TABS.RECENT'),
    icon: 'i-lucide-clock',
  },
  {
    key: 'favorites',
    label: t('OUTSIDER_WHATSAPP.STICKERS.TABS.FAVORITES'),
    icon: 'i-lucide-star',
  },
  {
    key: 'all',
    label: t('OUTSIDER_WHATSAPP.STICKERS.TABS.ALL'),
    icon: 'i-lucide-layout-grid',
  },
  ...packs.value.map(pack => ({
    key: pack.id,
    label: pack.name,
    icon: 'i-lucide-folder',
  })),
]);

const errorText = (error, fallbackKey) =>
  stickerErrorText(t, error, fallbackKey);

const closeMenus = () => {
  menuFor.value = null;
  moving.value = false;
  confirmDelete.value = null;
  newPackOpen.value = false;
  renaming.value = false;
  confirmPackDelete.value = false;
};

const close = () => {
  isOpen.value = false;
  closeMenus();
};

const toggle = async () => {
  if (isOpen.value) {
    close();
    return;
  }
  isOpen.value = true;
  await loadStickers(accountId.value);
  if (!tabs.value.some(item => item.key === tab.value)) tab.value = 'all';
  if (tab.value === 'all' && recent.value.length) tab.value = 'recent';
};

const pickTab = key => {
  closeMenus();
  tab.value = key;
};

// ---------- enviar ----------
const send = async sticker => {
  if (sendingId.value || !props.conversationId) return;
  closeMenus();
  sendingId.value = sticker.id;
  try {
    const { data } = await StickersAPI.send(sticker.id, props.conversationId);
    markUsed(sticker.id);
    if (data?.message) store.dispatch('addMessage', data.message);
  } catch (error) {
    useAlert(errorText(error, 'SEND_ERROR'));
  } finally {
    sendingId.value = null;
  }
};

// ---------- adicionar imagens ----------
const pickFiles = () => fileInput.value?.click();

const onFiles = async event => {
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  if (!files.length) return;
  const packId = activePack.value?.id || null;
  uploading.value = files.length;
  let existed = 0;
  await files.reduce(
    (chain, file) =>
      chain.then(async () => {
        try {
          const { data } = await StickersAPI.upload(file);
          let sticker = data.sticker;
          if (data.existed) existed += 1;
          if (packId && sticker.pack_id !== packId) {
            const response = await StickersAPI.update(sticker.id, {
              pack_id: packId,
            });
            sticker = response.data.sticker;
          }
          putSticker(sticker);
        } catch (error) {
          useAlert(
            errorText(error, 'UPLOAD_ERROR').replace('{name}', file.name)
          );
        } finally {
          uploading.value -= 1;
        }
      }),
    Promise.resolve()
  );
  if (existed) useAlert(t('OUTSIDER_WHATSAPP.STICKERS.EXISTED'));
  if (FIXED_TABS.includes(tab.value) && tab.value !== 'all') tab.value = 'all';
};

// ---------- menu da figurinha ----------
const openMenu = sticker => {
  if (menuFor.value === sticker.id) {
    closeMenus();
    return;
  }
  closeMenus();
  menuFor.value = sticker.id;
};

const patch = async (sticker, attributes) => {
  try {
    const { data } = await StickersAPI.update(sticker.id, attributes);
    putSticker(data.sticker);
  } catch (error) {
    useAlert(errorText(error, 'SAVE_ERROR'));
  }
};

const toggleFavorite = sticker => {
  closeMenus();
  patch(sticker, { favorite: !sticker.favorite });
};

const moveTo = (sticker, packId) => {
  closeMenus();
  patch(sticker, { pack_id: packId });
};

const remove = async sticker => {
  if (confirmDelete.value !== sticker.id) {
    confirmDelete.value = sticker.id;
    return;
  }
  closeMenus();
  try {
    await StickersAPI.remove(sticker.id);
    dropSticker(sticker.id);
  } catch (error) {
    useAlert(errorText(error, 'SAVE_ERROR'));
  }
};

// ---------- grupos ----------
const startNewPack = async () => {
  closeMenus();
  newPackOpen.value = true;
  newPackName.value = '';
  await nextTick();
  packInput.value?.focus();
};

const createPack = async (sticker = null) => {
  const name = newPackName.value.trim();
  if (!name) return;
  try {
    const { data } = await StickersAPI.createPack(name);
    putPack(data.pack);
    closeMenus();
    if (sticker) await patch(sticker, { pack_id: data.pack.id });
    tab.value = data.pack.id;
  } catch (error) {
    useAlert(errorText(error, 'SAVE_ERROR'));
  }
};

const startRename = async () => {
  if (!activePack.value) return;
  closeMenus();
  renaming.value = true;
  renameValue.value = activePack.value.name;
  await nextTick();
  packInput.value?.focus();
};

const renamePack = async () => {
  const name = renameValue.value.trim();
  if (!name || !activePack.value) return;
  try {
    const { data } = await StickersAPI.updatePack(activePack.value.id, {
      name,
    });
    putPack(data.pack);
    closeMenus();
  } catch (error) {
    useAlert(errorText(error, 'SAVE_ERROR'));
  }
};

const removePack = async () => {
  if (!activePack.value) return;
  if (!confirmPackDelete.value) {
    confirmPackDelete.value = true;
    return;
  }
  const id = activePack.value.id;
  try {
    await StickersAPI.removePack(id);
    dropPack(id);
    closeMenus();
    tab.value = 'all';
  } catch (error) {
    useAlert(errorText(error, 'SAVE_ERROR'));
  }
};

onClickOutside(rootRef, close);
onKeyStroke('Escape', () => {
  if (menuFor.value || newPackOpen.value || renaming.value) closeMenus();
  else close();
});
watch(() => props.conversationId, close);

defineExpose({ toggle, close });
</script>

<template>
  <div ref="rootRef" class="relative">
    <button
      v-tooltip.top-start="t('OUTSIDER_WHATSAPP.STICKERS.BUTTON')"
      type="button"
      class="grid transition-colors rounded-full size-9 place-content-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
      :class="{ 'bg-n-alpha-2 text-n-slate-12 ring-1 ring-n-strong': isOpen }"
      :aria-label="t('OUTSIDER_WHATSAPP.STICKERS.BUTTON')"
      :aria-expanded="isOpen"
      data-composer-stickers
      @click="toggle"
    >
      <Icon icon="i-ph-sticker" class="size-5" />
    </button>
    <input
      ref="fileInput"
      type="file"
      accept="image/png,image/jpeg,image/webp,image/gif"
      multiple
      class="hidden"
      @change="onFiles"
    />
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="translate-y-1 opacity-0"
      leave-active-class="transition duration-100 ease-in"
      leave-to-class="translate-y-1 opacity-0"
    >
      <div
        v-if="isOpen"
        class="absolute z-50 flex flex-col mb-2 border shadow-xl ltr:left-0 rtl:right-0 bottom-full w-[22.5rem] max-w-[calc(100vw-1rem)] h-[26rem] max-h-[calc(var(--outsider-app-height,100dvh)-8rem)] rounded-2xl bg-n-solid-2 border-n-weak"
        data-sticker-picker
        @click="confirmDelete = null"
      >
        <!-- cabeçalho -->
        <div class="flex items-center gap-1 px-3 pt-2.5 pb-1.5">
          <span class="flex-1 text-sm font-semibold text-n-slate-12">
            {{
              activePack
                ? activePack.name
                : t('OUTSIDER_WHATSAPP.STICKERS.TITLE')
            }}
          </span>
          <template v-if="activePack">
            <button
              type="button"
              class="grid rounded-full size-8 place-content-center text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('OUTSIDER_WHATSAPP.STICKERS.PACK.RENAME')"
              data-sticker-pack-rename
              @click.stop="startRename"
            >
              <span class="i-lucide-pencil size-4" />
            </button>
            <button
              type="button"
              class="grid rounded-full size-8 place-content-center hover:bg-n-alpha-2"
              :class="confirmPackDelete ? 'text-n-ruby-11' : 'text-n-slate-11'"
              :title="
                confirmPackDelete
                  ? t('OUTSIDER_WHATSAPP.STICKERS.PACK.DELETE_CONFIRM')
                  : t('OUTSIDER_WHATSAPP.STICKERS.PACK.DELETE')
              "
              data-sticker-pack-delete
              @click.stop="removePack"
            >
              <span
                :class="
                  confirmPackDelete ? 'i-lucide-trash' : 'i-lucide-trash-2'
                "
                class="size-4"
              />
            </button>
          </template>
          <button
            type="button"
            class="grid rounded-full size-8 place-content-center text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
            :title="t('OUTSIDER_WHATSAPP.STICKERS.ADD')"
            :disabled="uploading > 0"
            data-sticker-add
            @click.stop="pickFiles"
          >
            <span
              v-if="uploading"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            <span v-else class="i-lucide-image-plus size-4" />
          </button>
          <button
            type="button"
            class="grid rounded-full size-8 place-content-center text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('GENERAL.CLOSE')"
            @click.stop="close"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>

        <!-- renomear / novo grupo -->
        <form
          v-if="renaming || newPackOpen"
          class="flex items-center gap-2 px-3 pb-2"
          @submit.prevent="renaming ? renamePack() : createPack()"
        >
          <input
            ref="packInput"
            :value="renaming ? renameValue : newPackName"
            type="text"
            maxlength="40"
            class="flex-1 h-8 px-3 text-sm rounded-lg outline-none bg-n-alpha-1 text-n-slate-12 focus:ring-1 focus:ring-n-brand"
            :placeholder="t('OUTSIDER_WHATSAPP.STICKERS.PACK.NAME')"
            data-sticker-pack-name
            @input="
              renaming
                ? (renameValue = $event.target.value)
                : (newPackName = $event.target.value)
            "
          />
          <button
            type="submit"
            class="h-8 px-3 text-xs font-semibold text-white rounded-lg bg-n-brand"
          >
            {{
              renaming
                ? t('OUTSIDER_WHATSAPP.STICKERS.PACK.SAVE')
                : t('OUTSIDER_WHATSAPP.STICKERS.PACK.CREATE')
            }}
          </button>
          <button
            type="button"
            class="h-8 px-2 text-xs text-n-slate-11"
            @click="closeMenus"
          >
            {{ t('OUTSIDER_WHATSAPP.STICKERS.PACK.CANCEL') }}
          </button>
        </form>

        <!-- abas: recentes, favoritas, todas e os grupos -->
        <div
          class="flex gap-1 px-3 pb-2 overflow-x-auto no-scrollbar shrink-0"
          data-sticker-tabs
        >
          <button
            v-for="item in tabs"
            :key="item.key"
            type="button"
            class="flex items-center gap-1.5 h-7 px-2.5 text-xs rounded-full shrink-0 transition-colors"
            :class="
              tab === item.key
                ? 'bg-n-brand text-white'
                : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
            "
            :data-sticker-tab="item.key"
            @click.stop="pickTab(item.key)"
          >
            <span :class="item.icon" class="size-3.5 shrink-0" />
            <span class="max-w-[8rem] truncate">{{ item.label }}</span>
          </button>
          <button
            type="button"
            class="flex items-center gap-1 h-7 px-2.5 text-xs rounded-full shrink-0 border border-dashed border-n-strong text-n-slate-11 hover:bg-n-alpha-2"
            data-sticker-new-pack
            @click.stop="startNewPack"
          >
            <span class="i-lucide-plus size-3.5" />
            {{ t('OUTSIDER_WHATSAPP.STICKERS.PACK.NEW') }}
          </button>
        </div>

        <!-- grade -->
        <div class="flex-1 min-h-0 px-3 pb-3 overflow-y-auto">
          <div
            v-if="stickerState.loading && !stickerState.loaded"
            class="grid h-full text-sm place-content-center text-n-slate-11"
          >
            {{ t('OUTSIDER_WHATSAPP.STICKERS.LOADING') }}
          </div>
          <div
            v-else-if="stickerState.error && !stickerState.loaded"
            class="grid h-full gap-2 text-sm text-center place-content-center text-n-slate-11"
          >
            {{ t('OUTSIDER_WHATSAPP.STICKERS.LOAD_ERROR') }}
            <button
              type="button"
              class="font-semibold text-n-brand"
              @click.stop="loadStickers(accountId, true)"
            >
              {{ t('OUTSIDER_WHATSAPP.STICKERS.RETRY') }}
            </button>
          </div>
          <div
            v-else-if="!visible.length"
            class="grid h-full px-6 text-sm text-center place-content-center text-n-slate-11"
            data-sticker-empty
          >
            {{ t(`OUTSIDER_WHATSAPP.STICKERS.EMPTY.${emptyKey}`) }}
          </div>
          <div v-else class="grid grid-cols-4 gap-2" data-sticker-grid>
            <div
              v-for="sticker in visible"
              :key="sticker.id"
              class="relative group/tile"
            >
              <button
                type="button"
                class="grid w-full p-1 transition rounded-xl aspect-square place-items-center hover:bg-n-alpha-2 active:scale-95 disabled:opacity-60"
                :class="{ 'ring-2 ring-n-brand': menuFor === sticker.id }"
                :disabled="sendingId === sticker.id"
                :data-sticker-id="sticker.id"
                @click.stop="send(sticker)"
              >
                <img
                  :src="sticker.url"
                  alt=""
                  class="object-contain w-full h-full select-none"
                  loading="lazy"
                  draggable="false"
                />
                <span
                  v-if="sendingId === sticker.id"
                  class="absolute grid rounded-full inset-1 place-content-center bg-n-solid-2/70"
                >
                  <span
                    class="i-lucide-loader-circle size-5 animate-spin text-n-brand"
                  />
                </span>
              </button>
              <span
                v-if="sticker.favorite"
                class="absolute top-1 ltr:left-1 rtl:right-1 i-lucide-star size-3.5 text-n-amber-9 pointer-events-none"
              />
              <button
                type="button"
                class="absolute top-0.5 ltr:right-0.5 rtl:left-0.5 grid rounded-full size-6 place-content-center bg-n-solid-1/90 text-n-slate-11 shadow opacity-0 transition group-hover/tile:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:opacity-100"
                :class="{ '!opacity-100': menuFor === sticker.id }"
                :aria-label="t('OUTSIDER_WHATSAPP.STICKERS.MENU.OPTIONS')"
                :aria-expanded="menuFor === sticker.id"
                data-sticker-menu
                @click.stop="openMenu(sticker)"
              >
                <span class="i-lucide-ellipsis size-4" />
              </button>
              <!-- menu da figurinha -->
              <div
                v-if="menuFor === sticker.id"
                class="absolute z-10 top-7 ltr:right-0 rtl:left-0 min-w-[11rem] py-1 border shadow-lg rounded-xl bg-n-solid-1 border-n-weak text-sm"
                role="menu"
                data-sticker-menu-panel
                @click.stop
              >
                <button
                  type="button"
                  role="menuitem"
                  class="flex items-center w-full gap-2 px-3 py-1.5 text-left text-n-slate-12 hover:bg-n-alpha-1"
                  @click="toggleFavorite(sticker)"
                >
                  <span
                    :class="
                      sticker.favorite ? 'i-lucide-star-off' : 'i-lucide-star'
                    "
                    class="size-4 text-n-slate-11"
                  />
                  {{
                    sticker.favorite
                      ? t('OUTSIDER_WHATSAPP.STICKERS.MENU.UNFAVORITE')
                      : t('OUTSIDER_WHATSAPP.STICKERS.MENU.FAVORITE')
                  }}
                </button>
                <button
                  type="button"
                  role="menuitem"
                  class="flex items-center w-full gap-2 px-3 py-1.5 text-left text-n-slate-12 hover:bg-n-alpha-1"
                  :aria-expanded="moving"
                  @click="moving = !moving"
                >
                  <span class="i-lucide-folder-input size-4 text-n-slate-11" />
                  {{ t('OUTSIDER_WHATSAPP.STICKERS.MENU.MOVE') }}
                  <span
                    class="ltr:ml-auto rtl:mr-auto i-lucide-chevron-down size-3.5 text-n-slate-10"
                  />
                </button>
                <div v-if="moving" class="pb-1 ltr:pl-6 rtl:pr-6">
                  <button
                    v-for="pack in packs"
                    :key="pack.id"
                    type="button"
                    role="menuitem"
                    class="flex items-center w-full gap-2 px-3 py-1 text-left truncate text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
                    :disabled="sticker.pack_id === pack.id"
                    @click="moveTo(sticker, pack.id)"
                  >
                    {{ pack.name }}
                  </button>
                  <button
                    type="button"
                    role="menuitem"
                    class="flex items-center w-full gap-2 px-3 py-1 text-left text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
                    :disabled="!sticker.pack_id"
                    @click="moveTo(sticker, null)"
                  >
                    {{ t('OUTSIDER_WHATSAPP.STICKERS.MENU.NO_PACK') }}
                  </button>
                  <form
                    v-if="newPackOpen"
                    class="flex items-center gap-1 px-3 py-1"
                    @submit.prevent="createPack(sticker)"
                  >
                    <input
                      ref="packInput"
                      v-model="newPackName"
                      type="text"
                      maxlength="40"
                      class="w-full h-7 px-2 text-xs rounded-md outline-none bg-n-alpha-1 text-n-slate-12 focus:ring-1 focus:ring-n-brand"
                      :placeholder="t('OUTSIDER_WHATSAPP.STICKERS.PACK.NAME')"
                    />
                    <button
                      type="submit"
                      class="h-7 px-2 text-xs font-semibold text-white rounded-md bg-n-brand"
                    >
                      {{ t('OUTSIDER_WHATSAPP.STICKERS.PACK.CREATE') }}
                    </button>
                  </form>
                  <button
                    v-else
                    type="button"
                    role="menuitem"
                    class="flex items-center w-full gap-2 px-3 py-1 text-left text-n-brand hover:bg-n-alpha-1"
                    @click="
                      newPackOpen = true;
                      newPackName = '';
                    "
                  >
                    <span class="i-lucide-plus size-3.5" />
                    {{ t('OUTSIDER_WHATSAPP.STICKERS.MENU.NEW_PACK') }}
                  </button>
                </div>
                <button
                  type="button"
                  role="menuitem"
                  class="flex items-center w-full gap-2 px-3 py-1.5 text-left hover:bg-n-alpha-1"
                  :class="
                    confirmDelete === sticker.id
                      ? 'text-n-ruby-11 font-semibold'
                      : 'text-n-slate-12'
                  "
                  data-sticker-delete
                  @click="remove(sticker)"
                >
                  <span
                    class="i-lucide-trash-2 size-4"
                    :class="
                      confirmDelete === sticker.id
                        ? 'text-n-ruby-11'
                        : 'text-n-slate-11'
                    "
                  />
                  {{
                    confirmDelete === sticker.id
                      ? t('OUTSIDER_WHATSAPP.STICKERS.MENU.DELETE_CONFIRM')
                      : t('OUTSIDER_WHATSAPP.STICKERS.MENU.DELETE')
                  }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>
