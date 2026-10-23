<script setup>
// OUTSIDER: ficha de um item do catálogo só para consulta (quem não gerencia o catálogo): foto,
// preços, quantidades, descrição, principais características e equipamento, como entram na proposta.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ProductStock from './ProductStock.vue';
import { formatMoney } from '../../helpers';
import { KIND_COLORS, kindLabel } from './catalog';

defineProps({
  product: { type: Object, required: true },
});

const { t } = useI18n();

const price = cents => (cents ? formatMoney(cents) : '—');
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="flex flex-col gap-4 sm:flex-row">
      <div
        class="flex items-center justify-center overflow-hidden shrink-0 sm:w-56 aspect-[4/3] rounded-xl bg-n-alpha-1"
      >
        <img
          v-if="product.image_url"
          :src="product.image_url"
          :alt="product.name"
          class="object-contain w-full h-full p-2"
        />
        <Icon v-else icon="i-lucide-package" class="size-10 text-n-slate-8" />
      </div>
      <div class="flex flex-col flex-1 min-w-0 gap-3">
        <div class="flex flex-wrap items-center gap-1.5">
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
        <dl class="grid grid-cols-2 gap-3 mb-0">
          <div v-if="product.code" class="flex flex-col">
            <dt class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_CRM.CATALOG.FORM.CODE') }}
            </dt>
            <dd class="text-sm text-n-slate-12">{{ product.code }}</dd>
          </div>
          <div v-if="product.brand" class="flex flex-col">
            <dt class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_CRM.CATALOG.FORM.BRAND') }}
            </dt>
            <dd class="text-sm text-n-slate-12">{{ product.brand }}</dd>
          </div>
          <div class="flex flex-col">
            <dt class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_CRM.CATALOG.SALE') }}
            </dt>
            <dd class="text-sm tabular-nums text-n-slate-12">
              {{ price(product.sale_price_cents) }}
            </dd>
          </div>
          <div class="flex flex-col">
            <dt class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_CRM.CATALOG.RENTAL') }}
            </dt>
            <dd class="text-sm tabular-nums text-n-slate-12">
              {{ price(product.rental_price_cents) }}
            </dd>
          </div>
        </dl>
        <ProductStock :product="product" />
      </div>
    </div>

    <p
      v-if="product.description"
      class="mb-0 text-sm whitespace-pre-line text-n-slate-12"
    >
      {{ product.description }}
    </p>

    <section v-if="product.specs?.length" class="flex flex-col gap-2">
      <h4 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.CATALOG.SPECS.TITLE') }}
      </h4>
      <dl
        class="mb-0 overflow-hidden divide-y rounded-xl divide-n-weak outline outline-1 -outline-offset-1 outline-n-container"
      >
        <div
          v-for="(spec, index) in product.specs"
          :key="index"
          class="grid grid-cols-2 gap-3 px-3 py-2 text-sm"
          :class="
            spec.bold ? 'font-semibold text-n-slate-12' : 'text-n-slate-11'
          "
        >
          <dt>{{ spec.label }}</dt>
          <dd class="text-n-slate-12">{{ spec.value }}</dd>
        </div>
      </dl>
    </section>

    <section v-if="product.features?.length" class="flex flex-col gap-2">
      <h4 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.CATALOG.FEATURES.TITLE') }}
      </h4>
      <ul class="flex flex-col gap-1 mb-0 list-none">
        <li
          v-for="(feature, index) in product.features"
          :key="index"
          class="flex items-start gap-2 text-sm text-n-slate-12"
        >
          <Icon
            icon="i-lucide-check"
            class="mt-0.5 size-4 shrink-0 text-n-teal-10"
          />
          {{ feature }}
        </li>
      </ul>
    </section>
  </div>
</template>
