<script setup>
import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { debounce } from '@chatwoot/utils';
import SearchAPI from 'dashboard/api/search';
import ContactAPI from 'dashboard/api/contacts';

const emit = defineEmits(['update:results', 'update:active']);

const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');

const query = ref('');
const isSearching = ref(false);
const hiddenCount = ref(0);

const runSearch = debounce(async () => {
  const q = query.value.trim();

  if (q.length < 2) {
    emit('update:active', false);
    emit('update:results', []);
    hiddenCount.value = 0;
    return;
  }

  isSearching.value = true;
  emit('update:active', true);

  try {
    // 1. Busca por CONTATO (nome/telefone/email) - preciso, sem ruído
    //    de conteúdo de mensagem, ao contrário de search/conversations.
    //    Formato real da resposta: { payload: { contacts: [...] } }
    const { data } = await SearchAPI.contacts({ q });
    const contacts = data?.payload?.contacts ?? [];

    // 2. Para cada contato encontrado, busca as conversas dele via
    //    o endpoint já existente (o mesmo do painel "Conversas
    //    anteriores"). Chamado direto na API, não via Vuex, porque o
    //    getter do módulo contactConversations faz camelcaseKeys() e
    //    quebraria a renderização (ConversationList.vue espera
    //    snake_case: unread_count, meta.assignee, etc).
    //    Em lotes de 3 para não sobrecarregar o backend quando a busca
    //    casar com muitos contatos de uma vez.
    const BATCH_SIZE = 3;
    const conversationsPerContact = [];
    for (let i = 0; i < contacts.length; i += BATCH_SIZE) {
      const batch = contacts.slice(i, i + BATCH_SIZE);
      const batchResults = await Promise.all(
        batch.map(async contact => {
          try {
            const { data: convData } = await ContactAPI.getConversations(
              contact.id
            );
            return convData?.payload ?? [];
          } catch (error) {
            // eslint-disable-next-line no-console
            console.error(
              `[ConversationSearchBar] Falha ao buscar conversas do contato ${contact.id}:`,
              error
            );
            return [];
          }
        })
      );
      conversationsPerContact.push(...batchResults);
    }

    // 3. Achata e remove duplicatas reais (mesmo id de conversa)
    const uniqueConversations = [
      ...new Map(
        conversationsPerContact.flat().map(c => [c.id, c])
      ).values(),
    ];

    // 4. Aplica o escopo: admin vê tudo; agente comum só vê o que é
    //    dele ou não está atribuído a ninguém.
    const visibleConversations = isAdmin.value
      ? uniqueConversations
      : uniqueConversations.filter(
          c =>
            !c.meta?.assignee || c.meta.assignee.id === currentUser.value?.id
        );

    hiddenCount.value = uniqueConversations.length - visibleConversations.length;
    emit('update:results', visibleConversations);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[ConversationSearchBar] Falha na busca:', error);
    hiddenCount.value = 0;
    emit('update:results', []);
  } finally {
    isSearching.value = false;
  }
}, 400);

const onInput = () => {
  runSearch();
};

const clearSearch = () => {
  query.value = '';
  hiddenCount.value = 0;
  emit('update:active', false);
  emit('update:results', []);
};
</script>

<template>
  <div class="w-full px-3 py-2">
    <div
      class="grid grid-cols-[32px_minmax(0,1fr)_32px]
            items-center
            w-full
            h-10
            min-w-0
            box-sizing-border-box
            border
            border-n-weak
            rounded-lg
            bg-n-alpha-1
            overflow-hidden
            focus-within:ring-1
            focus-within:ring-n-brand"
    >
      <!-- Lupa -->
      <div
        class="flex
              items-center
              justify-center
              w-8
              h-10
              shrink-0
              text-n-slate-10"
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
        placeholder="Buscar conversa por nome ou telefone..."
        class="block
              w-full
              min-w-0
              h-10
              !m-0
              !p-0
              !border-0
              !outline-none
              !ring-0
              !bg-transparent
              appearance-none
              text-sm
              leading-5
              text-n-slate-12
              placeholder:text-n-slate-10
              truncate"
        @input="onInput"
      />

      <!-- Limpar -->
      <button
        v-if="query"
        type="button"
        class="flex
              items-center
              justify-center
              w-8
              h-10
              shrink-0
              !m-0
              !p-0
              text-n-slate-10
              hover:text-n-slate-12"
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
      Buscando...
    </div>
    <div
      v-else-if="hiddenCount > 0"
      class="mt-1 text-xs text-n-slate-11 text-center"
    >
      {{ hiddenCount }} resultado(s) fora do seu escopo — apenas
      administradores podem visualizá-los.
    </div>
  </div>
</template>
