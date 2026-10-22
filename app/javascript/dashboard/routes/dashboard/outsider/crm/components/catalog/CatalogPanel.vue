<script setup>
// OUTSIDER: aba Catálogo do CRM. Máquinas e acessórios que entram nas propostas, com foto,
// características, equipamento e preços. Todos consultam; quem gerencia o catálogo
// (access.proposals.manage_catalog) cadastra, altera, troca a imagem, desativa e apaga.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ProductCard from './ProductCard.vue';
import ProductDialog from './ProductDialog.vue';
import { errorMessage } from '../../helpers';

const props = defineProps({
  access: { type: Object, required: true },
});

const { t } = useI18n();

const dialogRef = ref(null);
const isLoading = ref(false);
const hasLoaded = ref(false);
const products = ref([]);
const searchText = ref('');
const filters = ref({ q: '', kind: '', inactive: false });

const canManage = computed(() =>
  Boolean(props.access?.proposals?.manage_catalog)
);

const kindFilters = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.CATALOG.FILTERS.ALL') },
  { value: 'machine', label: t('OUTSIDER_CRM.CATALOG.FILTERS.MACHINE') },
  { value: 'accessory', label: t('OUTSIDER_CRM.CATALOG.FILTERS.ACCESSORY') },
]);

const isFiltered = computed(() =>
  Boolean(filters.value.q || filters.value.kind)
);

// só a resposta da busca mais recente vale (digitar rápido dispara várias)
let lastRequest = 0;

const load = async () => {
  lastRequest += 1;
  const request = lastRequest;
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getProducts({
      q: filters.value.q || undefined,
      kind: filters.value.kind || undefined,
      all: canManage.value && filters.value.inactive ? 1 : undefined,
    });
    if (request === lastRequest) products.value = data;
  } catch (error) {
    if (request === lastRequest) useAlert(errorMessage(t, error));
  } finally {
    if (request === lastRequest) {
      isLoading.value = false;
      hasLoaded.value = true;
    }
  }
};

const applySearch = useDebounceFn(() => {
  filters.value.q = searchText.value.trim();
}, 300);

const openNew = () => dialogRef.value?.open(null, filters.value.kind);

const openProduct = product => dialogRef.value?.open(product);

watch(searchText, applySearch);
watch(filters, load, { deep: true });

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <div
        class="flex p-0.5 rounded-lg bg-n-alpha-2 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <Button
          v-for="option in kindFilters"
          :key="option.value"
          type="button"
          size="sm"
          :variant="filters.kind === option.value ? 'solid' : 'ghost'"
          :color="filters.kind === option.value ? 'blue' : 'slate'"
          :label="option.label"
          @click="filters.kind = option.value"
        />
      </div>
      <Input
        v-model="searchText"
        type="search"
        :placeholder="t('OUTSIDER_CRM.CATALOG.SEARCH')"
        :custom-input-class="['h-8 ltr:!pl-8 rtl:!pr-8 !py-1']"
        class="w-full sm:w-64"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
          />
        </template>
      </Input>
      <label
        v-if="canManage"
        class="flex items-center gap-2 text-sm cursor-pointer text-n-slate-11"
      >
        <Switch v-model="filters.inactive" />
        {{ t('OUTSIDER_CRM.CATALOG.FILTERS.SHOW_INACTIVE') }}
      </label>
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      <div class="flex-1" />
      <span v-if="products.length" class="text-sm text-n-slate-11">
        {{ t('OUTSIDER_CRM.CATALOG.COUNT', products.length) }}
      </span>
      <Button
        v-if="canManage"
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.CATALOG.NEW')"
        @click="openNew"
      />
    </div>

    <div v-if="!hasLoaded" class="flex justify-center p-8">
      <Spinner class="text-n-slate-10" />
    </div>

    <div
      v-else-if="!products.length"
      class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
    >
      <Icon icon="i-lucide-package" class="size-10 text-n-slate-9" />
      <p class="max-w-md mb-0 text-sm text-n-slate-11">
        <template v-if="isFiltered">
          {{ t('OUTSIDER_CRM.CATALOG.NO_RESULTS') }}
        </template>
        <template v-else-if="canManage">
          {{ t('OUTSIDER_CRM.CATALOG.EMPTY_MANAGER') }}
        </template>
        <template v-else>
          {{ t('OUTSIDER_CRM.CATALOG.EMPTY') }}
        </template>
      </p>
      <Button
        v-if="canManage && !isFiltered"
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.CATALOG.NEW')"
        @click="openNew"
      />
    </div>

    <div
      v-else
      class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
    >
      <ProductCard
        v-for="product in products"
        :key="product.id"
        :product="product"
        @click="openProduct(product)"
      />
    </div>

    <ProductDialog
      ref="dialogRef"
      :can-manage="canManage"
      @saved="load"
      @deleted="load"
    />
  </div>
</template>
