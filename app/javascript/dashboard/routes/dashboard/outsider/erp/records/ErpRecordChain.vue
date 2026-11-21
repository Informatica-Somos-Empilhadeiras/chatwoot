<script setup>
// OUTSIDER: a corrente do registro (orçamento -> OS -> pedido -> NF-e/NFS-e) em nós redondos ligados, como a jornada do
// CRM. O nó do registro aberto fica marcado; os outros abrem o registro no próprio painel, se o perfil de acesso deixa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate, formatMoney } from '../erpStore';
import { SCREENS, displayNumber, statusClass } from './recordsConfig';
import { allows } from '../../access/accessStore';

const props = defineProps({
  chain: { type: Array, default: () => [] },
});

const emit = defineEmits(['jump']);

const { t } = useI18n();
const ICONS = {
  quotes: 'i-lucide-file-text',
  orders: 'i-lucide-wrench',
  sales: 'i-lucide-shopping-cart',
  invoices: 'i-lucide-receipt-text',
  service_invoices: 'i-lucide-receipt',
};

const nodes = computed(() =>
  props.chain.map(node => ({ ...node, key: `${node.kind}:${node.numero}` }))
);

// cada tipo abre pela linha da aba dele no perfil de acesso
const canOpen = node => !!SCREENS[node.kind] && allows(SCREENS[node.kind]);
const idle = node => node.current || !canOpen(node);
const hint = node => {
  if (node.current) return '';
  return canOpen(node)
    ? t('OUTSIDER_ERP.RECORDS.CHAIN.OPEN')
    : t('OUTSIDER_ERP.RECORDS.NO_ACCESS_NODE');
};

const nodeClass = node => statusClass(node.status);
</script>

<template>
  <div class="flex items-start pb-1 overflow-x-auto">
    <template v-for="(node, index) in nodes" :key="node.key">
      <div
        class="relative flex flex-col items-center flex-1 min-w-[5.25rem] gap-1 px-0.5 text-center"
      >
        <span
          v-if="index"
          class="absolute left-0 h-0.5 right-1/2 top-5 bg-n-slate-6"
        />
        <span
          v-if="index < nodes.length - 1"
          class="absolute right-0 h-0.5 left-1/2 top-5 bg-n-slate-6"
        />
        <!-- o nó inteiro (bolinha e textos) abre o registro no painel -->
        <button
          type="button"
          class="relative z-[1] flex flex-col items-center gap-1 rounded-lg group focus-visible:outline-none disabled:opacity-100"
          :class="idle(node) ? 'cursor-default' : 'cursor-pointer'"
          :disabled="idle(node)"
          :title="hint(node)"
          @click="emit('jump', node)"
        >
          <span
            class="grid transition-transform rounded-full size-10 place-content-center"
            :class="[
              nodeClass(node),
              node.current
                ? 'ring-4 ring-n-brand/40'
                : !idle(node) &&
                  'group-hover:scale-110 group-focus-visible:ring-4 group-focus-visible:ring-n-brand',
            ]"
          >
            <Icon :icon="ICONS[node.kind]" class="size-4" />
          </span>
          <span
            class="text-[11px] font-medium leading-tight text-n-slate-12"
            :class="!idle(node) && 'group-hover:text-n-brand'"
          >
            {{ t(`OUTSIDER_ERP.RECORDS.CHAIN.${node.kind.toUpperCase()}`) }}
            {{ displayNumber(node) }}
          </span>
          <span
            v-if="node.status || node.entrada"
            class="text-[10px] leading-tight text-n-slate-10"
          >
            {{
              [
                node.status,
                node.entrada && t('OUTSIDER_ERP.RECORDS.CHAIN.INBOUND'),
              ]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
          <span
            v-if="node.total || node.data"
            class="text-[10px] leading-tight tabular-nums text-n-slate-10"
          >
            {{ node.total ? formatMoney(node.total) : formatDate(node.data) }}
          </span>
        </button>
      </div>
    </template>
  </div>
</template>
