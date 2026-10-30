<script setup>
// OUTSIDER: barra de busca da lista de conversas. Busca conversas, contatos e mensagens
// (useQuickSearch); os resultados aparecem no lugar da lista (QuickSearchResults.vue).
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useQuickSearch } from 'dashboard/composables/outsider/useQuickSearch';

const emit = defineEmits(['update:active']);

const { t } = useI18n();
const { state, isSearchActive, setQuery, clear } = useQuickSearch();

const query = computed({
  get: () => state.query,
  set: value => setQuery(value),
});

const onKeydown = event => {
  if (event.key === 'Escape') clear();
};

const clearSearch = () => {
  clear();
};

watch(isSearchActive, active => emit('update:active', active), {
  immediate: true,
});
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
        @keydown="onKeydown"
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
  </div>
</template>
