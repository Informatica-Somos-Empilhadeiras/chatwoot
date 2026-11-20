<script setup>
// OUTSIDER: a corrente do registro (orçamento -> OS -> pedido -> nota fiscal) em nós redondos ligados, como a jornada do
// CRM. O nó do registro aberto fica marcado; os outros abrem o registro na aba dele.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate, formatMoney } from '../erpStore';
import { statusClass } from './recordsConfig';

const props = defineProps({
  chain: { type: Array, default: () => [] },
});

const emit = defineEmits(['jump']);

const { t } = useI18n();
const ICONS = {
  quotes: 'i-lucide-file-text',
  orders: 'i-lucide-wrench',
  sales: 'i-lucide-shopping-cart',
  invoice: 'i-lucide-receipt-text',
};

// a nota fiscal do pedido entra como último nó (só mostra, não abre)
const nodes = computed(() =>
  props.chain.flatMap(node => {
    const list = [{ ...node, key: `${node.kind}:${node.numero}` }];
    if (node.kind === 'sales' && node.nota)
      list.push({ kind: 'invoice', numero: node.nota, key: `nf:${node.nota}` });
    return list;
  })
);

const nodeClass = node => {
  if (node.kind === 'invoice') return 'bg-n-blue-3 text-n-blue-11';
  return statusClass(node.status);
};
</script>

<template>
  <div class="flex items-start pb-1 overflow-x-auto">
    <template v-for="(node, index) in nodes" :key="node.key">
      <div
        class="relative flex flex-col items-center w-[6.5rem] gap-1 px-1 text-center shrink-0"
      >
        <span
          v-if="index"
          class="absolute left-0 h-0.5 right-1/2 top-5 bg-n-slate-6"
        />
        <span
          v-if="index < nodes.length - 1"
          class="absolute right-0 h-0.5 left-1/2 top-5 bg-n-slate-6"
        />
        <button
          type="button"
          class="relative z-[1] grid transition-transform rounded-full size-10 place-content-center"
          :class="[
            nodeClass(node),
            node.current
              ? 'ring-4 ring-n-brand/40 cursor-default'
              : node.kind === 'invoice'
                ? 'cursor-default'
                : 'hover:scale-110 focus-visible:ring-4 focus-visible:ring-n-brand',
          ]"
          :disabled="node.current || node.kind === 'invoice'"
          :title="
            node.kind === 'invoice' || node.current
              ? ''
              : t('OUTSIDER_ERP.RECORDS.CHAIN.OPEN')
          "
          @click="emit('jump', node)"
        >
          <Icon :icon="ICONS[node.kind]" class="size-4" />
        </button>
        <span class="text-[11px] font-medium leading-tight text-n-slate-12">
          {{ t(`OUTSIDER_ERP.RECORDS.CHAIN.${node.kind.toUpperCase()}`) }}
          {{ node.numero }}
        </span>
        <span
          v-if="node.status && node.kind !== 'invoice'"
          class="text-[10px] leading-tight text-n-slate-10"
        >
          {{ node.status }}
        </span>
        <span
          v-if="node.kind !== 'invoice' && (node.total || node.data)"
          class="text-[10px] leading-tight tabular-nums text-n-slate-10"
        >
          {{ node.total ? formatMoney(node.total) : formatDate(node.data) }}
        </span>
      </div>
    </template>
  </div>
</template>
