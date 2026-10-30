<script setup>
// OUTSIDER: resultados da busca da lista de conversas, no lugar da lista (como no WhatsApp):
// Conversas, Com outros agentes (com "Solicitar transferência"), Contatos, "Adicionar novo
// contato" e Mensagens (clicar leva até a mensagem dentro da conversa).
import { ref, computed, provide, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { useQuickSearch } from 'dashboard/composables/outsider/useQuickSearch';
import { jumpToMessage } from 'dashboard/composables/outsider/useConversationHistory';
import ConversationItem from 'dashboard/components/ConversationItem.vue';
import SearchLockedConversation from '../SearchLockedConversation.vue';
import QuickSearchContact from './QuickSearchContact.vue';
import QuickSearchMessage from './QuickSearchMessage.vue';
import NewContactDialog from './NewContactDialog.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  label: { type: String, default: '' },
  teamId: { type: [String, Number], default: 0 },
  foldersId: { type: [String, Number], default: 0 },
  conversationType: { type: String, default: '' },
  showAssignee: { type: Boolean, default: false },
});

const { t } = useI18n();
const router = useRouter();
const { state, searchTerms, refresh, loadMoreMessages } = useQuickSearch();

const accountId = useMapGetter('getCurrentAccountId');
const currentChat = useMapGetter('getSelectedChat');

const panelRef = ref(null);
const newContactRef = ref(null);
const createdContactId = ref(null);
const openedMessageId = ref(null);

// o card da conversa espera estes dois do ConversationList
provide('contextMenuElementTarget', panelRef);
provide('toggleContextMenu', () => {});

const messages = computed(() => state.messages);
const hasAnything = computed(
  () =>
    state.conversations.length ||
    state.locked.length ||
    state.contacts.length ||
    messages.value.list.length
);
const isFirstLoad = computed(
  () => state.loading && !hasAnything.value && !messages.value.list.length
);

const observerOptions = computed(() => ({
  root: panelRef.value,
  rootMargin: '200px 0px 200px 0px',
}));

const openNewContact = () => newContactRef.value?.open(state.query);

const onContactCreated = contact => {
  createdContactId.value = contact.id;
  refresh();
};

// conversa aberta: vai até a mensagem; outra conversa: abre nela e destaca as palavras
let stopWaiting = null;
const highlightWhenOpen = (conversationId, messageId, terms) => {
  stopWaiting?.();
  const timer = setTimeout(() => stopWaiting?.(), 10000);
  const stop = watch(
    () => currentChat.value?.id,
    id => {
      if (id !== conversationId) return;
      stopWaiting?.();
      setTimeout(() => jumpToMessage(messageId, { terms }), 400);
    }
  );
  stopWaiting = () => {
    clearTimeout(timer);
    stop();
    stopWaiting = null;
  };
};

const openMessage = hit => {
  openedMessageId.value = hit.id;
  const terms = [...searchTerms.value];
  const conversationId = hit.conversation.id;
  if (currentChat.value?.id === conversationId) {
    jumpToMessage(hit.id, { terms });
    return;
  }
  highlightWhenOpen(conversationId, hit.id, terms);
  router.push({
    path: frontendURL(
      conversationUrl({ accountId: accountId.value, id: conversationId })
    ),
    query: { messageId: hit.id },
  });
};
</script>

<template>
  <div
    ref="panelRef"
    class="flex-1 min-h-0 pb-4 overflow-y-auto conversations-list"
  >
    <div v-if="isFirstLoad" class="flex justify-center py-6">
      <Spinner class="text-n-brand" />
    </div>

    <p v-if="state.error" class="px-4 py-3 text-sm text-center text-n-ruby-11">
      {{ t('OUTSIDER_TOOLS.SEARCH.ERROR') }}
    </p>

    <!-- Conversas -->
    <section v-if="state.conversations.length">
      <h4
        class="px-4 pt-2 pb-1 text-xs font-semibold uppercase text-n-slate-10"
      >
        {{
          t('OUTSIDER_TOOLS.SEARCH.CONVERSATIONS', {
            count: state.conversations.length,
          })
        }}
      </h4>
      <ConversationItem
        v-for="conversation in state.conversations"
        :key="conversation.id"
        :source="conversation"
        :label="label"
        :team-id="teamId"
        :folders-id="foldersId"
        :conversation-type="conversationType"
        :show-assignee="showAssignee"
      />
    </section>

    <!-- Com outros agentes -->
    <section v-if="state.locked.length" class="px-3 pt-2">
      <h4 class="px-1 pb-1.5 text-xs font-semibold uppercase text-n-slate-10">
        {{
          t('CHAT_LIST.OUTSIDER_SEARCH.LOCKED_HEADING', {
            count: state.locked.length,
          })
        }}
      </h4>
      <div class="flex flex-col gap-1.5">
        <SearchLockedConversation
          v-for="conversation in state.locked"
          :key="conversation.id"
          :conversation="conversation"
        />
      </div>
    </section>

    <!-- Contatos + novo contato -->
    <section v-if="!isFirstLoad" class="px-1 pt-2">
      <h4
        v-if="state.contacts.length"
        class="px-3 pb-1 text-xs font-semibold uppercase text-n-slate-10"
      >
        {{
          t('OUTSIDER_TOOLS.SEARCH.CONTACTS', { count: state.contacts.length })
        }}
      </h4>
      <QuickSearchContact
        v-for="contact in state.contacts"
        :key="contact.id"
        :contact="contact"
        :highlighted="contact.id === createdContactId"
      />
      <button
        type="button"
        class="flex items-center w-full gap-3 px-3 py-2 rounded-lg text-start hover:bg-n-alpha-2"
        @click="openNewContact"
      >
        <span
          class="flex items-center justify-center rounded-full size-8 shrink-0 bg-n-brand/10 text-n-brand"
        >
          <Icon icon="i-lucide-user-plus" class="size-4" />
        </span>
        <span class="flex flex-col min-w-0">
          <span class="text-sm font-medium text-n-brand">
            {{ t('OUTSIDER_TOOLS.SEARCH.ADD_CONTACT') }}
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{
              t('OUTSIDER_TOOLS.SEARCH.ADD_CONTACT_HINT', {
                query: state.query.trim(),
              })
            }}
          </span>
        </span>
      </button>
    </section>

    <!-- Mensagens -->
    <section class="px-1 pt-3">
      <h4
        v-if="messages.list.length || messages.loading"
        class="flex items-center gap-2 px-3 pb-1 text-xs font-semibold uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_TOOLS.SEARCH.MESSAGES') }}
        <Spinner v-if="messages.loading" class="size-3 text-n-slate-10" />
      </h4>
      <QuickSearchMessage
        v-for="message in messages.list"
        :key="message.id"
        :message="message"
        :terms="searchTerms"
        :active="message.id === openedMessageId"
        @open="openMessage"
      />
      <p
        v-if="messages.tooShort"
        class="px-3 py-2 text-xs text-center text-n-slate-10"
      >
        {{ t('OUTSIDER_TOOLS.SEARCH.MESSAGES_TOO_SHORT') }}
      </p>
      <p
        v-else-if="messages.timeout"
        class="px-3 py-2 text-xs text-center text-n-amber-11"
      >
        {{ t('OUTSIDER_TOOLS.SEARCH.MESSAGES_TIMEOUT') }}
      </p>
      <p
        v-else-if="messages.error"
        class="px-3 py-2 text-xs text-center text-n-ruby-11"
      >
        {{ t('OUTSIDER_TOOLS.SEARCH.ERROR') }}
      </p>
      <p
        v-else-if="!messages.loading && !messages.list.length && !state.loading"
        class="px-3 py-2 text-xs text-center text-n-slate-10"
      >
        {{ t('OUTSIDER_TOOLS.SEARCH.NO_MESSAGES') }}
      </p>
      <div v-if="messages.loadingMore" class="flex justify-center py-3">
        <Spinner class="text-n-brand" />
      </div>
      <IntersectionObserver
        v-else-if="messages.hasMore"
        :options="observerOptions"
        @observed="loadMoreMessages"
      />
    </section>

    <NewContactDialog ref="newContactRef" @created="onContactCreated" />
  </div>
</template>
