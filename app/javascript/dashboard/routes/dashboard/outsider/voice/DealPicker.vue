<script setup>
// OUTSIDER: escolher o negócio do CRM de uma ligação (Entrega 26), no telefone durante a conversa e em Telefonia >
// Ligações depois dela. Sem busca, mostra os negócios abertos do cliente; a busca procura por título, nome,
// telefone ou e-mail do cliente (só os negócios que a pessoa vê no CRM, como na lista do CRM).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  // negócios sugeridos ({ id, title, code, stage }), normalmente os abertos do cliente
  suggestions: { type: Array, default: () => [] },
  // negócio vinculado agora ({ id, title }) ou null
  current: { type: Object, default: null },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['pick', 'cancel']);

const { t } = useI18n();

const query = ref('');
const results = ref([]);
const isSearching = ref(false);

const searching = computed(() => query.value.trim().length >= 2);
const list = computed(() =>
  (searching.value ? results.value : props.suggestions).filter(
    deal => deal.id !== props.current?.id
  )
);

const search = useDebounceFn(async term => {
  try {
    const { data } = await CrmAPI.getOpportunities({ q: term });
    if (term !== query.value.trim()) return;
    results.value = data.payload.map(deal => ({
      id: deal.id,
      title: deal.title,
      code: deal.code,
      contact: deal.contact?.name,
      status: deal.status,
    }));
  } catch {
    results.value = [];
  } finally {
    if (term === query.value.trim()) isSearching.value = false;
  }
}, 300);

watch(query, value => {
  const term = value.trim();
  if (term.length < 2) {
    results.value = [];
    isSearching.value = false;
    return;
  }
  isSearching.value = true;
  search(term);
});
</script>

<template>
  <div class="flex flex-col gap-2" data-testid="outsider-deal-picker">
    <div class="relative">
      <Icon
        icon="i-lucide-search"
        class="absolute -translate-y-1/2 size-4 top-1/2 ltr:left-2.5 rtl:right-2.5 text-n-slate-10"
      />
      <input
        v-model="query"
        type="search"
        autocomplete="off"
        :placeholder="t('OUTSIDER_VOICE.DEAL_LINK.SEARCH')"
        class="w-full !mb-0 h-9 ltr:pl-8 rtl:pr-8 ltr:pr-2 rtl:pl-2 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
        data-testid="outsider-deal-search"
      />
    </div>
    <span v-if="!searching && list.length" class="text-xs text-n-slate-11">
      {{ t('OUTSIDER_VOICE.DEAL_LINK.SUGGESTED') }}
    </span>
    <div v-if="isSearching" class="flex justify-center py-2 text-n-slate-10">
      <Spinner :size="16" />
    </div>
    <p
      v-else-if="!list.length && searching"
      class="px-1 mb-0 text-xs text-n-slate-11"
    >
      {{ t('OUTSIDER_VOICE.DEAL_LINK.EMPTY') }}
    </p>
    <div v-else class="flex flex-col max-h-48 overflow-y-auto">
      <button
        v-for="deal in list"
        :key="deal.id"
        type="button"
        class="flex items-center gap-2 px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2 disabled:opacity-50"
        :disabled="busy"
        data-testid="outsider-deal-option"
        @click="emit('pick', deal)"
      >
        <Icon icon="i-lucide-kanban" class="size-4 shrink-0 text-n-slate-11" />
        <span class="flex flex-col min-w-0">
          <span class="text-sm truncate text-n-slate-12">{{ deal.title }}</span>
          <span class="text-xs truncate text-n-slate-11">
            {{
              [deal.code, deal.contact || deal.stage]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
        </span>
      </button>
    </div>
    <div class="flex justify-end gap-1">
      <Button
        v-if="current"
        xs
        ghost
        ruby
        icon="i-lucide-unlink"
        :label="t('OUTSIDER_VOICE.DEAL_LINK.UNLINK')"
        :disabled="busy"
        data-testid="outsider-deal-unlink"
        @click="emit('pick', null)"
      />
      <Button
        xs
        ghost
        slate
        :label="t('OUTSIDER_VOICE.CALL.BACK')"
        @click="emit('cancel')"
      />
    </div>
  </div>
</template>
