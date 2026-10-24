<script setup>
// OUTSIDER: encaminhar mensagem (texto e anexos). Abre pelo botão ao lado da bolha ou pelo menu da
// mensagem (evento CMD_OPEN_CUSTOM_FORWARD). Desde a Entrega 21 a pessoa só escolhe o contato: a
// mensagem sai pela caixa da conversa em que ela está, como no WhatsApp. Os anexos são copiados no
// servidor (ver app/services/outsider/message_forward.rb). Nos grupos, a Evolution põe
// "**+55 ... - Nome:**" no começo do texto: isso não vai junto.
import { computed, ref, watch, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import ContactAPI from 'dashboard/api/contacts';
import MessageForwardAPI from 'dashboard/api/outsider/messageForward';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const inboxGetter = useMapGetter('inboxes/getInbox');

const dialogRef = ref(null);
const payload = ref(null);
const query = ref('');
const results = ref([]);
const isSearching = ref(false);
const selected = ref(null);
const isSending = ref(false);
let searchController = null;

const inbox = computed(() => inboxGetter.value(payload.value?.inboxId) || {});
const body = computed(() => {
  const { content, text } = payload.value || {};
  return splitSenderHeader(content ?? text).body || '';
});
const attachmentCount = computed(
  () => (payload.value?.attachments || []).length
);

const toItem = contact => ({
  id: contact.id,
  name: contact.name,
  detail: contact.phone_number || contact.email || '',
  thumbnail: contact.thumbnail || '',
  isGroup: String(contact.identifier || '').endsWith('@g.us'),
});

const search = useDebounceFn(async term => {
  searchController?.abort();
  if (term.trim().length < 2) {
    results.value = [];
    isSearching.value = false;
    return;
  }
  searchController = new AbortController();
  try {
    const { data } = await ContactAPI.search(term.trim(), 1, 'name', '', {
      signal: searchController.signal,
    });
    results.value = (data.payload || []).map(toItem);
    isSearching.value = false;
  } catch (error) {
    if (error?.name !== 'CanceledError') isSearching.value = false;
  }
}, 300);

watch(query, term => {
  isSearching.value = term.trim().length >= 2;
  search(term);
});

const open = data => {
  payload.value = data;
  query.value = '';
  results.value = [];
  selected.value = null;
  dialogRef.value?.open();
};

const errorMessage = error => {
  const code = error?.response?.data?.error;
  const key = `OUTSIDER_WHATSAPP.FORWARD.ERRORS.${String(code || '').toUpperCase()}`;
  return code && t(key) !== key
    ? t(key, { inbox: inbox.value.name })
    : t('OUTSIDER_WHATSAPP.FORWARD.ERRORS.DEFAULT');
};

const send = async () => {
  if (!selected.value || isSending.value) return;
  isSending.value = true;
  try {
    await MessageForwardAPI.forward({
      contactId: selected.value.id,
      inboxId: payload.value.inboxId,
      content: body.value
        ? `*${t('OUTSIDER_WHATSAPP.FORWARD.HEADER')}*\n\n${body.value}`
        : '',
      attachmentIds: (payload.value.attachments || []).map(item => item.id),
    });
    dialogRef.value?.close();
    useAlert(
      t('OUTSIDER_WHATSAPP.FORWARD.SENT', { name: selected.value.name })
    );
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSending.value = false;
  }
};

onMounted(() => emitter.on('CMD_OPEN_CUSTOM_FORWARD', open));
onUnmounted(() => emitter.off('CMD_OPEN_CUSTOM_FORWARD', open));
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_WHATSAPP.FORWARD.TITLE')"
    :description="
      inbox.name
        ? t('OUTSIDER_WHATSAPP.FORWARD.VIA', { inbox: inbox.name })
        : ''
    "
    :confirm-button-label="
      selected
        ? t('OUTSIDER_WHATSAPP.FORWARD.SEND_TO', { name: selected.name })
        : t('OUTSIDER_WHATSAPP.FORWARD.SEND')
    "
    :disable-confirm-button="!selected"
    :is-loading="isSending"
    width="md"
    @confirm="send"
  >
    <div class="flex flex-col gap-4" data-forward-dialog>
      <div
        v-if="body || attachmentCount"
        class="flex flex-col gap-1 px-3 py-2 text-sm rounded-lg bg-n-alpha-1 text-n-slate-11"
      >
        <span v-if="body" class="whitespace-pre-line line-clamp-3">
          {{ body }}
        </span>
        <span v-if="attachmentCount" class="flex items-center gap-1 text-xs">
          <Icon icon="i-lucide-paperclip" class="size-3.5" />
          {{
            t(
              'OUTSIDER_WHATSAPP.FORWARD.ATTACHMENTS',
              { count: attachmentCount },
              attachmentCount
            )
          }}
        </span>
      </div>

      <div class="relative">
        <Icon
          icon="i-lucide-search"
          class="absolute -translate-y-1/2 pointer-events-none size-4 left-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          type="search"
          class="w-full !mb-0 !pl-9 px-3 py-2 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
          :placeholder="t('OUTSIDER_WHATSAPP.FORWARD.SEARCH')"
          @keydown.enter.prevent
        />
      </div>

      <div class="flex flex-col -mx-1 overflow-y-auto max-h-64">
        <p
          v-if="isSearching"
          class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
        >
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.SEARCHING') }}
        </p>
        <p
          v-else-if="query.trim().length < 2"
          class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
        >
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.HINT') }}
        </p>
        <p
          v-else-if="!results.length"
          class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
        >
          {{ t('OUTSIDER_WHATSAPP.SEND_CONTACT.NO_RESULTS') }}
        </p>
        <template v-else>
          <button
            v-for="item in results"
            :key="item.id"
            type="button"
            class="flex items-center gap-3 px-2 py-2 text-left rounded-lg hover:bg-n-alpha-1"
            :class="{ 'bg-n-alpha-2': selected?.id === item.id }"
            data-forward-contact
            @click="selected = item"
          >
            <Avatar
              :name="item.name"
              :src="item.thumbnail"
              :size="32"
              rounded-full
            />
            <span class="flex flex-col flex-1 min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ item.name }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{
                  item.isGroup
                    ? t('OUTSIDER_WHATSAPP.FORWARD.GROUP')
                    : item.detail
                }}
              </span>
            </span>
            <Icon
              :icon="
                selected?.id === item.id
                  ? 'i-lucide-circle-check'
                  : 'i-lucide-circle'
              "
              class="size-5 shrink-0"
              :class="
                selected?.id === item.id ? 'text-n-teal-10' : 'text-n-slate-8'
              "
            />
          </button>
        </template>
      </div>
    </div>
  </Dialog>
</template>
