<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { debounce } from '@chatwoot/utils';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const isOpen = ref(false);
const isSearching = ref(false);
const isProcessing = ref(false);
const processingStatus = ref('');
const searchQuery = ref('');
const contacts = ref([]);
const selectedContact = ref(null);
const contactableInboxes = ref([]);
const payloadData = ref(null);

const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const searchContacts = createContactSearcher();

const openModal = data => {
  console.log("========== MENSAGEM RECEBIDA ==========");
  console.dir(data);
  console.log(JSON.stringify(data, null, 2));

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

const executeForward = async inbox => {
  console.group('========== FORWARD ==========');

  isProcessing.value = true;
  processingStatus.value = 'Preparando pacote...';

  try {
    console.log('Payload:', payloadData.value);
    console.log('Contato:', selectedContact.value);
    console.log('Inbox:', inbox);

    // ======================================================
    // DADOS DA INBOX
    // ======================================================

    const targetInboxId = inbox.inbox ? inbox.inbox.id : inbox.id;
    const targetSourceId = inbox.source_id;

    console.log('Inbox ID:', targetInboxId);
    console.log('Source ID:', targetSourceId);

    if (!targetInboxId) {
      throw new Error('Inbox inválida.');
    }

    // ======================================================
    // CRIA CONVERSA
    // ======================================================

    console.log('Criando conversa...');

    const convResponse = await window.axios.post(
      `/api/v1/accounts/${accountId.value}/conversations`,
      {
        contact_id: selectedContact.value.id,
        inbox_id: targetInboxId,
        source_id: targetSourceId,
      }
    );

    console.log('Resposta conversa:', convResponse);
    console.log('Data conversa:', convResponse.data);

    const targetConversationId = convResponse.data.id;

    console.log('Conversation ID:', targetConversationId);

    if (!targetConversationId) {
      throw new Error('A API não retornou ID da conversa.');
    }

    // ======================================================
    // PREPARA ANEXOS
    // ======================================================

    console.log('Preparando anexos...');

    // 3. Processamento de anexos usando o proxy interno do Chatwoot
    const filesToUpload = [];

    if (payloadData.value.attachments && payloadData.value.attachments.length > 0) {
      for (const att of payloadData.value.attachments) {
        try {
          // O objeto real usa camelCase
          const sourceUrl = att.dataUrl;

          console.log('URL original:', sourceUrl);

          if (!sourceUrl) continue;

          const res = await window.axios.get(sourceUrl, {
            responseType: 'blob',
            withCredentials: true,
          });

          console.log('STATUS:', res.status);
          console.log('CONTENT-TYPE:', res.headers['content-type']);
          console.log('SIZE:', res.data.size);

          console.log('Blob recebido:', res.data);

          const extension = att.extension || 'bin';
          const filename = `forwarded-${att.id}.${extension}`;

          const file = new File(
            [res.data],
            filename,
            {
              type: att.contentType || res.data.type || 'application/octet-stream',
            }
          );

          console.log('Arquivo criado:', file);

          filesToUpload.push(file);
        } catch (error) {
          console.error('Erro ao processar anexo:', error);
        }
      }
    }

    console.log('Arquivos prontos para upload:', filesToUpload);

    // ======================================================
    // TEXTO
    // ======================================================

    let textContent = payloadData.value.text
      ? `*[Mensagem Encaminhada]*\n\n${payloadData.value.text}`
      : '';

    if (!textContent && filesToUpload.length > 0) {
      textContent = '*[Mídia encaminhada]*';
    }

    if (!textContent && filesToUpload.length === 0) {
      textContent = '*[Falha ao encaminhar mídia]*';
    }

    console.log('Texto:', textContent);

    // ======================================================
    // ENVIO
    // ======================================================

    processingStatus.value = 'Enviando...';

    let payload;

    if (filesToUpload.length) {
      payload = new FormData();

      payload.append('content', textContent);
      payload.append('private', false);

      filesToUpload.forEach(file => {
        payload.append('attachments[]', file);
      });

      console.log('Enviando FormData');

      for (const pair of payload.entries()) {
        console.log(pair[0], pair[1]);
      }
    } else {
      payload = {
        content: textContent,
        private: false,
      };

      console.log('Enviando JSON');
      console.log(payload);
    }

    console.log('ANTES DO POST MESSAGE');

    const messageResponse = await window.axios.post(
      `/api/v1/accounts/${accountId.value}/conversations/${targetConversationId}/messages`,
      payload
    );

    console.log('DEPOIS DO POST MESSAGE');
    console.log(messageResponse);

    await store.dispatch('fetchConversations', {
      page: 1,
    });

    console.log('SUCESSO');

    useAlert('Mensagem encaminhada!');

    closeModal();
  } catch (error) {
    console.error('==============================');
    console.error('ERRO');

    console.error(error);

    if (error.response) {
      console.error('STATUS', error.response.status);
      console.error('DATA', error.response.data);
      console.error('HEADERS', error.response.headers);
    }

    if (error.request) {
      console.error('REQUEST', error.request);
    }

    console.error('MESSAGE', error.message);

    useAlert('Erro. Veja o Console.');
  } finally {
    console.groupEnd();

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
                {{ contact.name.charAt(0) }}
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
