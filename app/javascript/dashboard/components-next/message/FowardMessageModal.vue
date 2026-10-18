<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { debounce } from '@chatwoot/utils';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MessageForwardAPI from 'dashboard/api/outsider/messageForward';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';

const isOpen = ref(false);
const isSearching = ref(false);
const isProcessing = ref(false);
const processingStatus = ref('');
const searchQuery = ref('');
const contacts = ref([]);
const selectedContact = ref(null);
const contactableInboxes = ref([]);
const payloadData = ref(null);

const accountId = useMapGetter('getCurrentAccountId');
const searchContacts = createContactSearcher();

const openModal = data => {
  payloadData.value = data;
  isOpen.value = true;
};

const closeModal = () => {
  isOpen.value = false;
  resetState();
};

const resetState = () => {
  searchQuery.value = '';
  contacts.value = [];
  selectedContact.value = null;
  contactableInboxes.value = [];
  isProcessing.value = false;
  processingStatus.value = '';
};

const onSearch = debounce(async () => {
  if (searchQuery.value.length < 2) return;
  isSearching.value = true;
  try {
    const results = await searchContacts(searchQuery.value);
    if (results !== null) contacts.value = results;
  } catch (error) {
    useAlert('Erro ao buscar contatos.');
  } finally {
    isSearching.value = false;
  }
}, 400);

const selectContact = async contact => {
  selectedContact.value = contact;
  isProcessing.value = true;
  processingStatus.value = 'Buscando vias disponíveis...';

  try {
    const res = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/contacts/${contact.id}/contactable_inboxes`
    );

    contactableInboxes.value = res.data.payload;
  } catch (error) {
    useAlert('Erro ao carregar caixas de entrada do contato.');
  } finally {
    isProcessing.value = false;
  }
};

// Os anexos são copiados no servidor (ver app/services/outsider/message_forward.rb).
// Nos grupos, a Evolution põe "**+55 ... - Nome:**" no começo do texto: isso não vai junto.
const executeForward = async inbox => {
  isProcessing.value = true;
  processingStatus.value = 'Encaminhando...';

  try {
    const { content, text, attachments = [] } = payloadData.value;
    const { body } = splitSenderHeader(content ?? text);

    await MessageForwardAPI.forward({
      contactId: selectedContact.value.id,
      inboxId: inbox.inbox ? inbox.inbox.id : inbox.id,
      sourceId: inbox.source_id,
      content: body ? `*[Mensagem Encaminhada]*\n\n${body}` : '',
      attachmentIds: attachments.map(attachment => attachment.id),
    });

    useAlert('Mensagem encaminhada!');
    closeModal();
  } catch (error) {
    useAlert('Não foi possível encaminhar a mensagem. Tente de novo.');
  } finally {
    isProcessing.value = false;
  }
};

onMounted(() => {
  emitter.on('CMD_OPEN_CUSTOM_FORWARD', openModal);
});

onUnmounted(() => {
  emitter.off('CMD_OPEN_CUSTOM_FORWARD', openModal);
});
</script>

<template>
  <woot-modal :show="isOpen" :on-close="closeModal">
    <div class="flex flex-col p-6 min-h-[25rem] max-h-[40rem] bg-white dark:bg-n-solid-1 rounded-md shadow-xl">
      <h2 class="text-xl font-medium text-n-slate-12 mb-4">Encaminhar Mensagem</h2>

      <div v-if="isProcessing" class="flex flex-col flex-1 items-center justify-center">
        <Spinner class="text-n-brand mb-4 size-8" />
        <p class="text-sm text-n-slate-11 font-medium">{{ processingStatus }}</p>
      </div>

      <div v-else class="flex flex-col flex-1 overflow-hidden">
        <template v-if="!selectedContact">
          <input
            v-model="searchQuery"
            type="text"
            placeholder="Buscar contato (nome, telefone...)"
            class="w-full p-3 mb-4 text-sm border border-n-strong rounded-md bg-n-alpha-1 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
            @input="onSearch"
          />
          <div v-if="isSearching" class="text-xs text-n-slate-11 mb-2">Buscando...</div>

          <ul class="flex-1 overflow-y-auto space-y-2">
            <li
              v-for="contact in contacts"
              :key="contact.id"
              class="p-3 border border-n-weak rounded-md cursor-pointer hover:bg-n-alpha-2 transition-colors flex items-center gap-3"
              @click="selectContact(contact)"
            >
              <div class="size-8 rounded-full bg-n-brand/20 flex items-center justify-center text-n-brand font-bold">
                {{ (contact.name || '?').charAt(0) }}
              </div>
              <div>
                <div class="font-medium text-sm text-n-slate-12">{{ contact.name }}</div>
                <div class="text-xs text-n-slate-11">{{ contact.phone_number || contact.email }}</div>
              </div>
            </li>
          </ul>
        </template>

        <template v-else>
          <div class="mb-4 pb-4 border-b border-n-strong">
            <span class="text-sm text-n-slate-11">Contato selecionado: </span>
            <span class="text-sm font-bold text-n-slate-12">{{ selectedContact.name }}</span>
            <button class="ml-4 text-xs text-n-brand hover:underline" @click="selectedContact = null">
              Voltar
            </button>
          </div>

          <h3 class="text-sm font-medium text-n-slate-12 mb-3">Selecione a via para encaminhar:</h3>
          <ul v-if="contactableInboxes.length > 0" class="flex-1 overflow-y-auto space-y-2">
            <li
              v-for="inbox in contactableInboxes"
              :key="inbox.inbox_id || inbox.source_id"
              class="p-3 border border-n-strong rounded-md cursor-pointer bg-n-alpha-1 hover:bg-n-brand/10 transition-colors flex justify-between items-center"
              @click="executeForward(inbox)"
            >
              <div>
                <div class="text-sm font-bold text-n-slate-12">{{ inbox.inbox.name }}</div>
                <div class="text-xs text-n-slate-11 uppercase mt-1">
                  {{ inbox.inbox.channel_type.replace('Channel::', '') }}
                </div>
              </div>
              <span class="i-lucide-send size-5 text-n-brand" />
            </li>
          </ul>
          <div v-else class="text-sm text-n-slate-11 p-4 text-center border border-dashed border-n-strong rounded-md">
            O contato selecionado não possui identificadores válidos (telefone/email) vinculados a caixas de entrada.
          </div>
        </template>
      </div>
    </div>
  </woot-modal>
</template>
