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
import { isEvolutionInbox } from 'dashboard/helper/outsider/whatsappMessage';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const inboxGetter = useMapGetter('inboxes/getInbox');

// OUTSIDER: dá para encaminhar várias mensagens (modo seleção, payload.messages) para até
// MAX_RECIPIENTS contatos de uma vez, como no WhatsApp. Cada mensagem sai com a mesma chamada de
// sempre, uma por vez e na ordem da conversa.
const MAX_RECIPIENTS = 5;
// a Evolution espera um pouco (aleatório) antes de mandar cada mensagem: com um intervalo entre
// elas a ordem chega certa no celular do contato
const EVOLUTION_GAP_MS = 1500;
const wait = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const dialogRef = ref(null);
const payload = ref(null);
const query = ref('');
const results = ref([]);
const isSearching = ref(false);
const selected = ref([]);
const isSending = ref(false);
const progress = ref({ done: 0, total: 0 });
let searchController = null;

const inbox = computed(() => inboxGetter.value(payload.value?.inboxId) || {});

const withoutHeader = content => splitSenderHeader(content).body || '';

// lista do que vai: uma mensagem (botão/menu) ou várias (seleção)
const items = computed(() => {
  const data = payload.value;
  if (!data) return [];
  const list = data.messages || [
    { content: data.content ?? data.text, attachments: data.attachments },
  ];
  return list
    .map(item => ({
      body: withoutHeader(item.content),
      attachmentIds: (item.attachments || []).map(file => file.id),
    }))
    .filter(item => item.body || item.attachmentIds.length);
});
const isMany = computed(() => items.value.length > 1);
const body = computed(() => (isMany.value ? '' : items.value[0]?.body || ''));
const attachmentCount = computed(() =>
  items.value.reduce((sum, item) => sum + item.attachmentIds.length, 0)
);
const skipped = computed(() => payload.value?.skipped || 0);

const isSelected = item => selected.value.some(one => one.id === item.id);
const toggle = item => {
  if (isSelected(item)) {
    selected.value = selected.value.filter(one => one.id !== item.id);
  } else if (selected.value.length < MAX_RECIPIENTS) {
    selected.value = [...selected.value, item];
  } else {
    useAlert(
      t('OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.MAX', { max: MAX_RECIPIENTS })
    );
  }
};

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
  selected.value = [];
  progress.value = { done: 0, total: 0 };
  dialogRef.value?.open();
};

const errorMessage = error => {
  const code = error?.response?.data?.error;
  const key = `OUTSIDER_WHATSAPP.FORWARD.ERRORS.${String(code || '').toUpperCase()}`;
  return code && t(key) !== key
    ? t(key, { inbox: inbox.value.name })
    : t('OUTSIDER_WHATSAPP.FORWARD.ERRORS.DEFAULT');
};

const title = computed(() =>
  isMany.value
    ? t('OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.TITLE', {
        count: items.value.length,
      })
    : t('OUTSIDER_WHATSAPP.FORWARD.TITLE')
);

const confirmLabel = computed(() => {
  if (isSending.value && progress.value.total > 1) {
    return t('OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.PROGRESS', progress.value);
  }
  if (selected.value.length > 1) {
    return t('OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.TO_MANY', {
      count: selected.value.length,
    });
  }
  if (selected.value.length === 1) {
    return t('OUTSIDER_WHATSAPP.FORWARD.SEND_TO', {
      name: selected.value[0].name,
    });
  }
  return t('OUTSIDER_WHATSAPP.FORWARD.SEND');
});

const forwardOne = (contact, item) =>
  MessageForwardAPI.forward({
    contactId: contact.id,
    inboxId: payload.value.inboxId,
    content: item.body
      ? `*${t('OUTSIDER_WHATSAPP.FORWARD.HEADER')}*\n\n${item.body}`
      : '',
    attachmentIds: item.attachmentIds,
  });

const send = async () => {
  if (!selected.value.length || !items.value.length || isSending.value) return;
  isSending.value = true;
  const recipients = [...selected.value];
  const gap = isEvolutionInbox(inbox.value) ? EVOLUTION_GAP_MS : 0;
  progress.value = { done: 0, total: recipients.length * items.value.length };
  let failed = 0;
  let lastError = null;
  const jobs = recipients.flatMap(contact =>
    items.value.map((item, index) => ({ contact, item, index }))
  );
  // uma de cada vez, na ordem
  await jobs.reduce(
    (chain, { contact, item, index }) =>
      chain.then(async () => {
        if (index > 0 && gap) await wait(gap);
        try {
          await forwardOne(contact, item);
        } catch (error) {
          failed += 1;
          lastError = error;
        }
        progress.value = { ...progress.value, done: progress.value.done + 1 };
      }),
    Promise.resolve()
  );
  isSending.value = false;
  const { total } = progress.value;
  if (failed === total) {
    useAlert(errorMessage(lastError));
    return;
  }
  dialogRef.value?.close();
  emitter.emit('OUTSIDER_FORWARD_DONE');
  if (failed) {
    useAlert(
      t('OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.PARTIAL', { failed, total })
    );
  } else if (recipients.length > 1) {
    useAlert(
      t('OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.SENT_MANY', {
        count: recipients.length,
      })
    );
  } else if (isMany.value) {
    useAlert(
      t(
        'OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.SENT',
        { count: items.value.length, name: recipients[0].name },
        items.value.length
      )
    );
  } else {
    useAlert(t('OUTSIDER_WHATSAPP.FORWARD.SENT', { name: recipients[0].name }));
  }
};

onMounted(() => emitter.on('CMD_OPEN_CUSTOM_FORWARD', open));
onUnmounted(() => emitter.off('CMD_OPEN_CUSTOM_FORWARD', open));
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="
      inbox.name
        ? t('OUTSIDER_WHATSAPP.FORWARD.VIA', { inbox: inbox.name })
        : ''
    "
    :confirm-button-label="confirmLabel"
    :disable-confirm-button="!selected.length || !items.length"
    :is-loading="isSending"
    width="md"
    @confirm="send"
  >
    <div class="flex flex-col gap-4" data-forward-dialog>
      <div
        v-if="body || attachmentCount || isMany"
        class="flex flex-col gap-1 px-3 py-2 text-sm rounded-lg bg-n-alpha-1 text-n-slate-11"
      >
        <template v-if="isMany">
          <span
            v-for="(item, index) in items.slice(0, 3)"
            :key="index"
            class="truncate"
          >
            <span
              v-if="item.attachmentIds.length"
              class="i-lucide-paperclip size-3.5 align-middle"
            />
            {{ item.body || t('CHAT_LIST.ATTACHMENTS.file.CONTENT') }}
          </span>
          <span v-if="items.length > 3" class="text-xs">
            +{{ items.length - 3 }}
          </span>
        </template>
        <span v-if="body" class="whitespace-pre-line line-clamp-3">
          {{ body }}
        </span>
        <span
          v-if="skipped"
          class="flex items-center gap-1 text-xs text-n-amber-11"
        >
          <Icon icon="i-lucide-info" class="size-3.5" />
          {{ t('OUTSIDER_WHATSAPP.LOOK.SELECT.NOT_FORWARDABLE') }}
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

      <div
        v-if="selected.length"
        class="flex flex-wrap items-center gap-1.5"
        data-forward-recipients
      >
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_WHATSAPP.LOOK.FORWARD_MANY.SELECTED') }}
        </span>
        <button
          v-for="item in selected"
          :key="item.id"
          type="button"
          class="inline-flex items-center gap-1 py-0.5 ltr:pl-0.5 ltr:pr-2 rtl:pr-0.5 rtl:pl-2 text-xs font-medium rounded-full bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4"
          @click="toggle(item)"
        >
          <Avatar
            :name="item.name"
            :src="item.thumbnail"
            :size="18"
            rounded-full
          />
          {{ item.name }}
          <Icon icon="i-lucide-x" class="size-3" />
        </button>
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
            :class="{ 'bg-n-alpha-2': isSelected(item) }"
            data-forward-contact
            @click="toggle(item)"
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
                isSelected(item) ? 'i-lucide-circle-check' : 'i-lucide-circle'
              "
              class="size-5 shrink-0"
              :class="isSelected(item) ? 'text-n-teal-10' : 'text-n-slate-8'"
            />
          </button>
        </template>
      </div>
    </div>
  </Dialog>
</template>
