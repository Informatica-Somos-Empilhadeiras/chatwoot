<script setup>
// OUTSIDER: aba Produtos da seção ERP: consulta do cadastro de produtos e serviços do Mais Prático, só leitura. À
// esquerda a busca (código, código de fábrica ou palavras do nome) na unidade escolhida; à direita o produto aberto
// por inteiro, com as fotos (ErpProductDetail).
import { ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpProductDetail from './ErpProductDetail.vue';
import { erpState, erpErrorMessage, formatMoney } from '../erpStore';

const { t } = useI18n();
const company = ref(erpState.companies[0] || '');
const query = ref('');
const loading = ref(false);
const failure = ref('');
const products = ref([]);
const selected = ref(null);
let lastRun = 0;

const load = async () => {
  if (!company.value) return;
  lastRun += 1;
  const mine = lastRun;
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await ErpAPI.catalog(company.value, query.value.trim());
    if (mine !== lastRun) return;
    products.value = data.products || [];
  } catch (error) {
    if (mine === lastRun) {
      products.value = [];
      failure.value = erpErrorMessage(t, error);
    }
  } finally {
    if (mine === lastRun) loading.value = false;
  }
};

watch(query, debounce(load, 300));
watch(company, () => {
  selected.value = null;
  load();
});
onMounted(load);

const SELECT =
  '!mb-0 h-9 px-2 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6';
</script>

<template>
  <div
    class="flex flex-col gap-4 md:h-full md:grid md:grid-cols-[minmax(18rem,26rem)_minmax(0,1fr)]"
  >
    <aside
      class="flex flex-col min-h-0 overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex gap-2 p-3 border-b border-n-weak">
        <label
          class="flex items-center flex-1 min-w-0 gap-2 px-2 rounded-lg h-9 bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-slate-6 focus-within:outline-n-brand"
        >
          <Icon
            icon="i-lucide-search"
            class="size-4 text-n-slate-10 shrink-0"
          />
          <input
            v-model="query"
            type="search"
            class="!mb-0 flex-1 min-w-0 h-full text-sm bg-transparent reset-base text-n-slate-12 placeholder:text-n-slate-10"
            :placeholder="t('OUTSIDER_ERP.BUDGET.ITEMS.SEARCH')"
          />
          <Spinner v-if="loading" class="size-3.5 text-n-slate-10" />
        </label>
        <select
          v-if="erpState.companies.length > 1"
          v-model="company"
          :class="SELECT"
          :aria-label="t('OUTSIDER_ERP.RECORDS.UNIT')"
        >
          <option v-for="item in erpState.companies" :key="item" :value="item">
            {{ item }}
          </option>
        </select>
      </div>
      <div class="flex-1 min-h-0 overflow-y-auto max-h-[50vh] md:max-h-none">
        <p v-if="failure" class="p-3 mb-0 text-xs text-n-ruby-11">
          {{ failure }}
          <button type="button" class="underline" @click="load">
            {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
          </button>
        </p>
        <p
          v-else-if="!products.length && !loading"
          class="p-3 mb-0 text-xs text-n-slate-10"
        >
          {{ t('OUTSIDER_ERP.BUDGET.ITEMS.NONE') }}
        </p>
        <button
          v-for="product in products"
          :key="product.codigo"
          type="button"
          class="flex items-center w-full gap-3 px-3 py-2 text-left border-b last:border-b-0 border-n-weak"
          :class="
            selected === product.codigo
              ? 'bg-n-alpha-2 shadow-[inset_3px_0_0_rgb(var(--color-brand))]'
              : 'hover:bg-n-alpha-1'
          "
          @click="selected = product.codigo"
        >
          <span
            class="flex items-center justify-center rounded-lg shrink-0 size-8 bg-n-alpha-2 text-n-slate-11"
          >
            <Icon
              :icon="
                product.tipo === 1 ? 'i-lucide-wrench' : 'i-lucide-package'
              "
              class="size-4"
            />
          </span>
          <span class="flex flex-col flex-1 min-w-0">
            <span
              class="text-sm font-medium truncate text-n-slate-12"
              :title="product.descricao"
            >
              {{ product.codigo }} · {{ product.descricao }}
            </span>
            <span class="text-xs truncate text-n-slate-10">
              {{
                [formatMoney(product.preco), product.unidade]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </span>
        </button>
      </div>
    </aside>
    <section
      class="min-h-0 p-4 overflow-y-auto border rounded-xl border-n-weak bg-n-solid-1 sm:p-5"
    >
      <ErpProductDetail
        v-if="selected"
        :key="`${company}:${selected}`"
        :company="company"
        :code="selected"
      />
      <div
        v-else
        class="flex flex-col items-center justify-center h-full gap-3 p-10 text-center"
      >
        <Icon icon="i-lucide-package-search" class="size-10 text-n-slate-9" />
        <p class="max-w-sm mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_ERP.PRODUCTS.PICK') }}
        </p>
      </div>
    </section>
  </div>
</template>
