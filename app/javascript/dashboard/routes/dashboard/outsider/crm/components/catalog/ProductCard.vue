<script setup>
// OUTSIDER: cartão de um item do catálogo na grade: foto, nome, código, marca, tipo, preços e, quando
// o item controla, as quantidades disponível e reservada. O botão "Criar proposta" fica no próprio cartão
// (Entrega 21) para não precisar abrir o item; clicar no resto do cartão abre o item.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ProductStock from './ProductStock.vue';
import { formatMoney } from '../../helpers';
import { KIND_COLORS, kindLabel } from './catalog';

defineProps({
  product: { type: Object, required: true },
});

const emit = defineEmits(['open', 'createProposal']);

const { t } = useI18n();

const price = cents => (cents ? formatMoney(cents) : '—');
</script>

<template>
  <div
    class="flex flex-col overflow-hidden transition-colors rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container hover:outline-n-slate-6"
  >
    <button
      type="button"
      class="flex flex-col flex-1 text-start"
      @click="emit('open')"
    >
      <div
        class="relative flex items-center justify-center w-full aspect-[4/3] bg-n-alpha-1"
        :class="{ 'opacity-60': !product.active }"
      >
        <img
          v-if="product.image_url"
          :src="product.image_url"
          :alt="product.name"
          loading="lazy"
          class="object-contain w-full h-full p-2"
        />
        <Icon v-else icon="i-lucide-package" class="size-10 text-n-slate-8" />
        <div class="absolute flex flex-wrap gap-1 top-2 ltr:left-2 rtl:right-2">
          <span
            class="px-1.5 py-0.5 text-xs font-medium rounded-md"
            :class="KIND_COLORS[product.kind]"
          >
            {{ kindLabel(t, product.kind) }}
          </span>
          <span
            v-if="!product.active"
            class="px-1.5 py-0.5 text-xs font-medium rounded-md bg-n-slate-3 text-n-slate-11"
          >
            {{ t('OUTSIDER_CRM.CATALOG.INACTIVE') }}
          </span>
        </div>
      </div>
      <div class="flex flex-col flex-1 gap-1 p-3">
        <span
          class="text-sm font-medium line-clamp-2"
          :class="product.active ? 'text-n-slate-12' : 'text-n-slate-10'"
        >
          {{ product.name }}
        </span>
        <span
          v-if="product.code || product.brand"
          class="text-xs truncate text-n-slate-11"
        >
          {{ [product.code, product.brand].filter(Boolean).join(' · ') }}
        </span>
        <ProductStock :product="product" />
        <div class="flex-1" />
        <div class="grid grid-cols-2 gap-2 pt-2 mt-1 border-t border-n-weak">
          <div class="flex flex-col min-w-0">
            <span class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_CRM.CATALOG.SALE') }}
            </span>
            <span class="text-sm truncate tabular-nums text-n-slate-12">
              {{ price(product.sale_price_cents) }}
            </span>
          </div>
          <div class="flex flex-col min-w-0">
            <span class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_CRM.CATALOG.RENTAL') }}
            </span>
            <span class="text-sm truncate tabular-nums text-n-slate-12">
              {{ price(product.rental_price_cents) }}
            </span>
          </div>
        </div>
      </div>
    </button>
    <div v-if="product.active" class="px-3 pb-3">
      <Button
        type="button"
        size="sm"
        variant="faded"
        color="blue"
        icon="i-lucide-file-plus"
        class="w-full"
        :label="t('OUTSIDER_CRM.CATALOG.PROPOSE.CREATE')"
        @click="emit('createProposal')"
      />
    </div>
  </div>
</template>
