<script setup>
// OUTSIDER: um produto do ERP por inteiro, só leitura (aba Produtos): cabeçalho (preço, estoque, unidade...), as fotos
// numa grade que se ajusta à quantidade (uma ocupa tudo; com mais, as colunas aumentam), a descrição técnica e os demais
// campos preenchidos do cadastro (Outsider::Erp::ProductDetail, sem custo nem margem). Clicar numa foto abre o
// carrossel (ErpPhotoViewer).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ErpAPI from 'dashboard/api/outsider/erp';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ErpPhotoViewer from './ErpPhotoViewer.vue';
import { erpState, erpErrorMessage, formatMoney } from '../erpStore';
import { formatQty } from '../budgets/budgetHelpers';
import { photoUrl, gridLayout } from './photoCache';

const props = defineProps({
  company: { type: String, required: true },
  code: { type: Number, required: true },
});

const { t } = useI18n();
const loading = ref(false);
const failure = ref('');
const detail = ref(null);
const urls = ref({});
const broken = ref({});
const viewerRef = ref(null);
let lastRun = 0;

const product = computed(() => detail.value?.produto || {});
const photos = computed(() => detail.value?.fotos || []);
const layout = computed(() => gridLayout(photos.value.length));

const loadPhotos = () => {
  photos.value.forEach(photo => {
    photoUrl(props.company, props.code, photo.id)
      .then(url => {
        urls.value = { ...urls.value, [photo.id]: url };
      })
      .catch(() => {
        broken.value = { ...broken.value, [photo.id]: true };
      });
  });
};

const load = async () => {
  lastRun += 1;
  const mine = lastRun;
  loading.value = true;
  failure.value = '';
  urls.value = {};
  broken.value = {};
  try {
    const { data } = await ErpAPI.product(props.company, props.code);
    if (mine !== lastRun) return;
    detail.value = data;
    loadPhotos();
  } catch (error) {
    if (mine === lastRun) {
      detail.value = null;
      failure.value = erpErrorMessage(t, error);
    }
  } finally {
    if (mine === lastRun) loading.value = false;
  }
};

watch(() => [props.company, props.code], load, { immediate: true });

const openPhoto = position =>
  viewerRef.value?.open({
    company: props.company,
    code: props.code,
    title: product.value.descricao,
    photos: photos.value,
    index: position,
  });

const stockText = computed(() => {
  const { tipo, estoque } = product.value;
  if (tipo === 1 || estoque === null || estoque === undefined) return '';
  return estoque > 0
    ? t('OUTSIDER_ERP.BUDGET.ITEMS.STOCK', { count: formatQty(estoque) })
    : t('OUTSIDER_ERP.BUDGET.ITEMS.NO_STOCK');
});
</script>

<template>
  <div class="flex flex-col gap-5">
    <div v-if="loading && !detail" class="flex justify-center p-10">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else-if="failure"
      class="flex flex-col items-center gap-3 p-8 text-center rounded-xl bg-n-alpha-1"
    >
      <p class="mb-0 text-sm text-n-ruby-11">{{ failure }}</p>
      <Button
        size="sm"
        variant="faded"
        color="slate"
        :label="t('OUTSIDER_ERP.CONTACT.RETRY')"
        @click="load"
      />
    </div>
    <template v-else-if="detail">
      <header class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-10">
          {{ t('OUTSIDER_ERP.PRODUCTS.CODE', { code: product.codigo }) }}
          <template v-if="product.fabrica">
            ·
            {{ t('OUTSIDER_ERP.PRODUCTS.FACTORY', { code: product.fabrica }) }}
          </template>
        </span>
        <h2 class="mb-0 text-lg font-medium text-n-slate-12">
          {{ product.descricao }}
        </h2>
        <div class="flex flex-wrap items-center gap-2 text-sm">
          <span class="font-medium tabular-nums text-n-slate-12">
            {{ formatMoney(product.preco) }}
          </span>
          <span v-if="product.unidade" class="text-n-slate-11">
            {{ product.unidade }}
          </span>
          <span
            v-if="product.tipo === 1"
            class="px-1.5 text-xs rounded bg-n-blue-3 text-n-blue-11"
          >
            {{ t('OUTSIDER_ERP.BUDGET.ITEMS.SERVICE') }}
          </span>
          <span
            v-else-if="stockText"
            class="text-xs"
            :class="product.estoque > 0 ? 'text-n-teal-11' : 'text-n-ruby-11'"
          >
            {{ stockText }}
          </span>
          <span v-if="product.bloqueado" class="text-xs text-n-ruby-11">
            {{ t('OUTSIDER_ERP.BUDGET.ITEMS.BLOCKED') }}
          </span>
          <span v-if="product.ncm" class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_ERP.BUDGET.ITEMS.NCM', { ncm: product.ncm }) }}
          </span>
        </div>
      </header>

      <section v-if="erpState.productPhotos" class="flex flex-col gap-2">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.PRODUCTS.PHOTOS.TITLE') }}
        </h3>
        <p v-if="!photos.length" class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_ERP.PRODUCTS.PHOTOS.NONE') }}
        </p>
        <div v-else class="grid gap-2" :class="layout.grid">
          <button
            v-for="(photo, position) in photos"
            :key="photo.id"
            type="button"
            class="flex items-center justify-center overflow-hidden rounded-xl bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-brand"
            :class="layout.cell"
            :title="photo.nome"
            @click="openPhoto(position)"
          >
            <img
              v-if="urls[photo.id]"
              :src="urls[photo.id]"
              :alt="photo.nome"
              class="object-contain w-full h-full"
            />
            <span
              v-else-if="broken[photo.id]"
              class="flex flex-col items-center gap-1 px-2 text-xs text-center text-n-slate-10"
            >
              <Icon icon="i-lucide-image-off" class="size-5" />
              {{ t('OUTSIDER_ERP.PRODUCTS.PHOTOS.MISSING_SHORT') }}
            </span>
            <Spinner v-else class="size-4 text-n-slate-10" />
          </button>
        </div>
      </section>

      <section class="flex flex-col gap-1">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.BUDGET.ITEMS.TECHNICAL') }}
        </h3>
        <p class="mb-0 text-sm whitespace-pre-line text-n-slate-11">
          {{ detail.tecnica || t('OUTSIDER_ERP.BUDGET.ITEMS.NO_TECHNICAL') }}
        </p>
      </section>

      <section v-if="detail.campos?.length" class="flex flex-col gap-2">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.PRODUCTS.FIELDS') }}
        </h3>
        <dl
          class="grid mb-0 overflow-hidden text-sm border sm:grid-cols-2 rounded-xl border-n-weak"
        >
          <div
            v-for="[label, value] in detail.campos"
            :key="label"
            class="flex flex-col gap-0.5 px-3 py-2 border-b border-n-weak min-w-0"
          >
            <dt class="text-xs text-n-slate-10">{{ label }}</dt>
            <dd class="mb-0 break-words text-n-slate-12">{{ value }}</dd>
          </div>
        </dl>
      </section>
    </template>
    <ErpPhotoViewer ref="viewerRef" />
  </div>
</template>
