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
import ErpPhotoThumb from './ErpPhotoThumb.vue';
import {
  erpState,
  erpErrorMessage,
  formatMoney,
  companyName,
} from '../erpStore';

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
    // código exato digitado: já abre o produto
    const exact = products.value.find(
      product => String(product.codigo) === query.value.trim()
    );
    if (exact) selected.value = exact.codigo;
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
</script>

<template>
  <div
    class="flex flex-col gap-4 md:h-full md:grid md:grid-cols-[minmax(18rem,26rem)_minmax(0,1fr)]"
  >
    <aside
      class="flex flex-col min-h-0 overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex flex-col gap-2 p-3 border-b border-n-weak">
        <div class="relative">
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 pointer-events-none size-4 left-3 top-1/2 text-n-slate-10"
          />
          <input
            v-model="query"
            type="text"
            :placeholder="t('OUTSIDER_ERP.PRODUCTS.SEARCH')"
            class="!mb-0 w-full h-10 pl-9 pr-9 text-sm rounded-xl reset-base bg-n-alpha-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-2 focus:outline-n-brand"
          />
          <Spinner
            v-if="loading"
            class="absolute -translate-y-1/2 right-3 top-1/2 size-4 text-n-slate-10"
          />
        </div>
        <div
          v-if="erpState.companies.length > 1"
          class="grid grid-cols-2 gap-0.5 p-0.5 rounded-lg bg-n-alpha-2"
          role="radiogroup"
          :aria-label="t('OUTSIDER_ERP.RECORDS.UNIT')"
        >
          <button
            v-for="item in erpState.companies"
            :key="item"
            type="button"
            role="radio"
            :aria-checked="company === item"
            class="h-7 px-2.5 text-xs rounded-md truncate"
            :class="
              company === item
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            :title="item"
            @click="company = item"
          >
            {{ companyName(item) }}
          </button>
        </div>
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
          <ErpPhotoThumb
            v-if="product.fotos"
            :company="company"
            :code="product.codigo"
            :count="product.fotos"
            size="size-11"
            @open="selected = product.codigo"
          />
          <span
            v-else
            class="flex items-center justify-center rounded-lg shrink-0 size-11 bg-n-alpha-2 text-n-slate-11"
          >
            <Icon
              :icon="
                product.tipo === 1 ? 'i-lucide-wrench' : 'i-lucide-package'
              "
              class="size-5"
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
