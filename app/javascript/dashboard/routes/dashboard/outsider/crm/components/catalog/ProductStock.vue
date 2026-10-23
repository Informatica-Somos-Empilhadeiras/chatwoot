<script setup>
// OUTSIDER: quantidades disponível e reservada de um item do catálogo (só as preenchidas).
import { useI18n } from 'vue-i18n';
import { hasStock } from './catalog';

defineProps({
  product: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <div v-if="hasStock(product)" class="flex flex-wrap gap-1">
    <span
      v-if="product.available_quantity != null"
      class="px-1.5 py-0.5 text-xs rounded-md tabular-nums"
      :class="
        product.available_quantity > 0
          ? 'bg-n-teal-3 text-n-teal-11'
          : 'bg-n-ruby-3 text-n-ruby-11'
      "
    >
      {{
        t('OUTSIDER_CRM.CATALOG.STOCK.AVAILABLE', {
          count: product.available_quantity,
        })
      }}
    </span>
    <span
      v-if="product.reserved_quantity"
      class="px-1.5 py-0.5 text-xs rounded-md tabular-nums bg-n-amber-3 text-n-amber-11"
    >
      {{
        t('OUTSIDER_CRM.CATALOG.STOCK.RESERVED', {
          count: product.reserved_quantity,
        })
      }}
    </span>
  </div>
</template>
