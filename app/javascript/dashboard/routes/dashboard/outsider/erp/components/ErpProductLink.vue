<script setup>
// OUTSIDER: vincula um produto do catálogo do CRM a um produto do ERP (CodigoProduto de uma unidade). Assim o item
// da proposta vira uma linha do orçamento no ERP com o imposto certo (as funções do ERP calculam pelo cadastro do
// produto). Sem vínculo, o item é "livre" e fica de fora do orçamento. Some com a integração desligada.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { erpState } from '../erpStore';

const code = defineModel({ type: [Number, String], default: null });

const { t } = useI18n();

const open = ref(false);
const company = ref(erpState.companies[0] || '');
const query = ref('');
const results = ref([]);
const searching = ref(false);

const search = async () => {
  if (!company.value || query.value.trim().length < 2) {
    results.value = [];
    return;
  }
  searching.value = true;
  try {
    const { data } = await ErpAPI.catalog(company.value, query.value.trim());
    results.value = data.products || [];
  } catch {
    results.value = [];
  } finally {
    searching.value = false;
  }
};

const choose = product => {
  code.value = product.codigo;
  open.value = false;
  query.value = '';
  results.value = [];
};

const clear = () => {
  code.value = null;
};

const toggle = () => {
  open.value = !open.value;
  if (!open.value) results.value = [];
};
</script>

<template>
  <div v-if="erpState.enabled" class="flex flex-col gap-1.5 text-sm">
    <span class="font-medium text-n-slate-12">
      {{ t('OUTSIDER_ERP.PRODUCT_LINK.TITLE') }}
    </span>

    <div v-if="code" class="flex items-center gap-2">
      <span
        class="flex items-center gap-1.5 px-2 py-1 text-xs rounded-lg bg-n-teal-3 text-n-teal-11"
      >
        <Icon icon="i-lucide-link" class="size-3.5" />
        {{ t('OUTSIDER_ERP.PRODUCT_LINK.LINKED', { code }) }}
      </span>
      <Button
        type="button"
        size="xs"
        variant="ghost"
        color="slate"
        :label="t('OUTSIDER_ERP.PRODUCT_LINK.CHANGE')"
        @click="toggle"
      />
      <Button
        type="button"
        size="xs"
        variant="ghost"
        color="ruby"
        icon="i-lucide-unlink"
        :label="t('OUTSIDER_ERP.PRODUCT_LINK.UNLINK')"
        @click="clear"
      />
    </div>
    <Button
      v-else
      type="button"
      size="sm"
      variant="faded"
      color="slate"
      icon="i-lucide-link"
      :label="t('OUTSIDER_ERP.PRODUCT_LINK.LINK')"
      @click="toggle"
    />

    <div
      v-if="open"
      class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <div class="flex flex-wrap items-center gap-2">
        <select
          v-if="erpState.companies.length > 1"
          v-model="company"
          class="!mb-0 h-8 px-2 py-0 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <option v-for="item in erpState.companies" :key="item" :value="item">
            {{ item }}
          </option>
        </select>
        <input
          v-model="query"
          type="text"
          :placeholder="t('OUTSIDER_ERP.PRODUCT_LINK.SEARCH_PLACEHOLDER')"
          class="!mb-0 flex-1 min-w-[10rem] h-8 px-2 text-sm rounded-lg"
          @keydown.enter.prevent="search"
        />
        <Button
          type="button"
          size="sm"
          icon="i-lucide-search"
          :label="t('OUTSIDER_ERP.PRODUCT_LINK.SEARCH')"
          :is-loading="searching"
          @click="search"
        />
      </div>
      <div v-if="searching" class="flex justify-center py-2">
        <Spinner class="text-n-slate-10" />
      </div>
      <ul v-else-if="results.length" class="flex flex-col gap-1 m-0 list-none">
        <li v-for="product in results" :key="product.codigo">
          <button
            type="button"
            class="flex items-center justify-between w-full gap-2 px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2"
            @click="choose(product)"
          >
            <span class="min-w-0 truncate text-n-slate-12">
              {{ product.descricao }}
            </span>
            <span class="text-xs shrink-0 text-n-slate-10">
              #{{ product.codigo }}
            </span>
          </button>
        </li>
      </ul>
      <p v-else class="mb-0 text-xs text-n-slate-10">
        {{ t('OUTSIDER_ERP.PRODUCT_LINK.HINT') }}
      </p>
    </div>
  </div>
</template>
