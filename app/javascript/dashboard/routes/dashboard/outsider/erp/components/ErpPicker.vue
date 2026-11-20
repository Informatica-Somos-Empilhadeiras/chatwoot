<script setup>
// OUTSIDER: lista do ERP que já abre carregada, com um filtro em cima (nome, código...). Quem usa passa a busca
// (search: texto => linhas) e o desenho de cada linha (slot "row"); aqui fica o campo, a espera, o vazio, o erro e a
// escolha (clique na linha). Usada para clientes (vínculo do contato) e produtos (vínculo do catálogo).
import { ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { erpErrorMessage } from '../erpStore';

const props = defineProps({
  search: { type: Function, required: true },
  rowKey: { type: Function, required: true },
  placeholder: { type: String, default: '' },
  emptyText: { type: String, default: '' },
  // muda a fonte (ex.: a unidade): recarrega a lista
  source: { type: String, default: '' },
  // linha sendo gravada (mostra a espera nela)
  busy: { type: String, default: '' },
});

const emit = defineEmits(['select']);

const { t } = useI18n();
const query = ref('');
const rows = ref([]);
const loading = ref(false);
const failure = ref('');
let lastRun = 0;

const run = async () => {
  lastRun += 1;
  const mine = lastRun;
  loading.value = true;
  failure.value = '';
  try {
    const list = await props.search(query.value.trim());
    if (mine === lastRun) rows.value = list || [];
  } catch (error) {
    if (mine === lastRun) {
      rows.value = [];
      failure.value = erpErrorMessage(t, error);
    }
  } finally {
    if (mine === lastRun) loading.value = false;
  }
};

const runLater = debounce(run, 350);
watch(query, runLater);
watch(() => props.source, run);
onMounted(run);
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <div class="relative">
      <Icon
        icon="i-lucide-search"
        class="absolute -translate-y-1/2 pointer-events-none size-3.5 left-2 top-1/2 text-n-slate-10"
      />
      <input
        v-model="query"
        type="text"
        :placeholder="placeholder"
        class="!mb-0 w-full h-8 pl-7 pr-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
      />
      <Spinner
        v-if="loading && rows.length"
        class="absolute -translate-y-1/2 right-2 top-1/2 size-3.5 text-n-slate-10"
      />
    </div>
    <div
      class="flex flex-col overflow-y-auto max-h-64 rounded-lg bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-slate-6"
    >
      <div v-if="loading && !rows.length" class="flex justify-center p-3">
        <Spinner class="text-n-slate-10" />
      </div>
      <p v-else-if="failure" class="p-2 mb-0 text-xs text-n-ruby-11">
        {{ failure }}
        <button type="button" class="underline" @click="run">
          {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
        </button>
      </p>
      <p v-else-if="!rows.length" class="p-2 mb-0 text-xs text-n-slate-10">
        {{ emptyText }}
      </p>
      <button
        v-for="row in rows"
        :key="rowKey(row)"
        type="button"
        class="flex items-center justify-between w-full gap-2 px-2 py-1.5 text-left border-b last:border-b-0 border-n-weak hover:bg-n-alpha-2 disabled:opacity-60"
        :disabled="Boolean(busy)"
        @click="emit('select', row)"
      >
        <div class="flex flex-col min-w-0">
          <slot name="row" :row="row" />
        </div>
        <Spinner
          v-if="busy === rowKey(row)"
          class="shrink-0 size-4 text-n-slate-10"
        />
        <Icon
          v-else
          icon="i-lucide-link"
          class="shrink-0 size-3.5 text-n-slate-10"
        />
      </button>
    </div>
  </div>
</template>
