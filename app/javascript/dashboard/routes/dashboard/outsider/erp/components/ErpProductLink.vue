<script setup>
// OUTSIDER: vincula um produto do catálogo do CRM a um produto do ERP (CodigoProduto de uma unidade). Assim o item
// da proposta vira uma linha do orçamento no ERP com o imposto certo (as funções do ERP calculam pelo cadastro do
// produto). Sem vínculo, o item é "livre" e fica de fora do orçamento. Some com a integração desligada. A lista de
// produtos da unidade já abre carregada e filtra por número ou descrição (ErpPicker).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpPicker from './ErpPicker.vue';
import { erpState } from '../erpStore';

const code = defineModel({ type: [Number, String], default: null });

const { t } = useI18n();

const open = ref(false);
const company = ref(erpState.companies[0] || '');

const searchProducts = async q => {
  if (!company.value) return [];
  const { data } = await ErpAPI.catalog(company.value, q);
  return data.products || [];
};
const productKey = product => String(product.codigo);

const choose = product => {
  code.value = product.codigo;
  open.value = false;
};

const clear = () => {
  code.value = null;
};

const toggle = () => {
  open.value = !open.value;
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
      <select
        v-if="erpState.companies.length > 1"
        v-model="company"
        class="!mb-0 h-8 px-2 py-0 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <option v-for="item in erpState.companies" :key="item" :value="item">
          {{ item }}
        </option>
      </select>
      <ErpPicker
        :search="searchProducts"
        :row-key="productKey"
        :source="company"
        :placeholder="t('OUTSIDER_ERP.PRODUCT_LINK.SEARCH_PLACEHOLDER')"
        :empty-text="t('OUTSIDER_ERP.PRODUCT_LINK.EMPTY')"
        @select="choose"
      >
        <template #row="{ row }">
          <span class="text-sm truncate text-n-slate-12">
            {{ row.descricao }}
          </span>
          <span class="text-xs text-n-slate-10">#{{ row.codigo }}</span>
        </template>
      </ErpPicker>
      <p class="mb-0 text-xs text-n-slate-10">
        {{ t('OUTSIDER_ERP.PRODUCT_LINK.HINT') }}
      </p>
    </div>
  </div>
</template>
