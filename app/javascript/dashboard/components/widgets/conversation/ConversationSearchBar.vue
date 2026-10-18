<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { debounce } from '@chatwoot/utils';
import ConversationSearchAPI from 'dashboard/api/outsider/conversationSearch';
import SearchLockedConversation from './SearchLockedConversation.vue';

const emit = defineEmits(['update:results', 'update:active']);

const store = useStore();
const { t } = useI18n();

const query = ref('');
const isSearching = ref(false);
// conversas com outros agentes: aparecem aqui, sem abrir, para saber com quem está o contato
const lockedResults = ref([]);
// só vale a resposta da última busca (quem digita rápido dispara várias)
let lastRequest = 0;

const reset = () => {
  lastRequest += 1;
  isSearching.value = false;
  lockedResults.value = [];
  emit('update:active', false);
  emit('update:results', []);
};

// O servidor já devolve uma conversa por contato e caixa (a não resolvida ou a mais
// recente), só das caixas do agente, e marca as que estão com outro agente.
const runSearch = debounce(async () => {
  const q = query.value.trim();
  if (q.length < 2) {
    reset();
    return;
  }

  lastRequest += 1;
  const request = lastRequest;
  isSearching.value = true;
  emit('update:active', true);

  try {
    const { data } = await ConversationSearchAPI.search(q);
    if (request !== lastRequest) return;

    const conversations = data.payload;
    // o card da lista pega o nome e a foto do contato na store
    conversations.forEach(conversation =>
      store.dispatch('contacts/setContact', conversation.meta.sender)
    );
    lockedResults.value = conversations.filter(c => c.outsider_locked);
    emit(
      'update:results',
      conversations.filter(c => !c.outsider_locked)
    );
  } catch (error) {
    if (request !== lastRequest) return;
    // eslint-disable-next-line no-console
    console.error('[ConversationSearchBar] Falha na busca:', error);
    lockedResults.value = [];
    emit('update:results', []);
  } finally {
    if (request === lastRequest) isSearching.value = false;
  }
}, 300);

const onInput = () => {
  runSearch();
};

const clearSearch = () => {
  query.value = '';
  reset();
};
</script>

<template>
  <div class="w-full px-3 py-2">
    <div
      class="grid grid-cols-[32px_minmax(0,1fr)_32px] items-center w-full h-10 min-w-0 box-sizing-border-box border border-n-weak rounded-lg bg-n-alpha-1 overflow-hidden focus-within:ring-1 focus-within:ring-n-brand"
    >
      <!-- Lupa -->
      <div
        class="flex items-center justify-center w-8 h-10 shrink-0 text-n-slate-10"
      >
        <svg
          class="block size-4 shrink-0"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
      </div>

      <!-- Campo de busca -->
      <input
        v-model="query"
        type="text"
        :placeholder="t('CHAT_LIST.OUTSIDER_SEARCH.PLACEHOLDER')"
        class="block w-full min-w-0 h-10 !m-0 !p-0 !border-0 !outline-none !ring-0 !bg-transparent appearance-none text-sm leading-5 text-n-slate-12 placeholder:text-n-slate-10 truncate"
        @input="onInput"
      />

      <!-- Limpar -->
      <button
        v-if="query"
        type="button"
        class="flex items-center justify-center w-8 h-10 shrink-0 !m-0 !p-0 text-n-slate-10 hover:text-n-slate-12"
        @click="clearSearch"
      >
        <svg
          class="block size-4"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>
    </div>

    <div v-if="isSearching" class="mt-1 text-xs text-n-slate-11 text-center">
      {{ t('CHAT_LIST.OUTSIDER_SEARCH.SEARCHING') }}
    </div>
    <div v-if="lockedResults.length" class="mt-2">
      <p class="px-1 mb-1.5 text-xs font-medium text-n-slate-11">
        {{
          t('CHAT_LIST.OUTSIDER_SEARCH.LOCKED_HEADING', {
            count: lockedResults.length,
          })
        }}
      </p>
      <div class="flex flex-col gap-1.5 overflow-y-auto max-h-72">
        <SearchLockedConversation
          v-for="conversation in lockedResults"
          :key="conversation.id"
          :conversation="conversation"
        />
      </div>
    </div>
  </div>
</template>
