<script setup>
// OUTSIDER: peças e serviços do orçamento. Quantidade, valor e desconto (%) se editam direto na linha; a busca de produto
// fica embaixo da tabela (ErpProductSearch), assim a lista que abre não tapa os itens já escolhidos.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ErpProductSearch from './ErpProductSearch.vue';
import {
  formatNumber,
  formatQty,
  lineTotal,
  parseNumber,
} from './budgetHelpers';

const props = defineProps({
  company: { type: String, required: true },
  readOnly: { type: Boolean, default: false },
  // desconto livre até este % (acima, a linha fica em vermelho e o orçamento pede liberação); null = sem limite
  discountMax: { type: Number, default: null },
});

const items = defineModel({ type: Array, default: () => [] });

const { t } = useI18n();
const searchRef = ref(null);

const add = item => {
  items.value = [...items.value, item];
};

const remove = index => {
  items.value = items.value.filter((_, position) => position !== index);
};

const update = (index, field, value) => {
  items.value = items.value.map((item, position) =>
    position === index ? { ...item, [field]: value } : item
  );
};

// ao sair do campo, o número volta formatado (1.234,56); vazio volta ao mínimo
const normalize = (index, field) => {
  const item = items.value[index];
  const fallback = field === 'quantidade' ? 1 : 0;
  const number = parseNumber(item[field], fallback);
  update(index, field, field === 'quantidade' && number <= 0 ? 1 : number);
};

const overLimit = item =>
  props.discountMax !== null && parseNumber(item.desconto) > props.discountMax;

const shown = (item, field) => {
  const value = item[field];
  if (typeof value !== 'number') return value;
  if (field === 'quantidade') return formatQty(value);
  return field === 'preco'
    ? formatNumber(value)
    : formatNumber(value, value % 1 ? 2 : 0);
};

const INPUT =
  '!mb-0 h-8 px-2 text-sm text-right rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand disabled:opacity-70';
const ROW =
  'flex flex-wrap items-center gap-2 sm:grid sm:grid-cols-[2rem_3.5rem_minmax(0,1fr)_4.5rem_6.5rem_4.5rem_6rem_1.75rem] sm:gap-3';

defineExpose({ focusSearch: () => searchRef.value?.focus() });
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-if="items.length"
      :class="ROW"
      class="hidden px-1 pb-1 text-[11px] font-medium tracking-wide uppercase border-b sm:grid text-n-slate-10 border-n-weak"
    >
      <span />
      <span>{{ t('OUTSIDER_ERP.BUDGET.ITEMS.CODE') }}</span>
      <span>{{ t('OUTSIDER_ERP.BUDGET.ITEMS.DESCRIPTION') }}</span>
      <span class="text-right">{{ t('OUTSIDER_ERP.BUDGET.ITEMS.QTY') }}</span>
      <span class="text-right">{{ t('OUTSIDER_ERP.BUDGET.ITEMS.PRICE') }}</span>
      <span class="text-right">{{
        t('OUTSIDER_ERP.BUDGET.ITEMS.DISCOUNT')
      }}</span>
      <span class="text-right">{{ t('OUTSIDER_ERP.BUDGET.ITEMS.TOTAL') }}</span>
      <span />
    </div>

    <div
      v-for="(item, index) in items"
      :key="`${item.codigo}-${index}`"
      :class="ROW"
      class="px-1 py-1.5 border-b border-n-weak last:border-b-0"
    >
      <span
        class="items-center justify-center hidden rounded-lg sm:flex size-8 bg-n-alpha-2 text-n-slate-11"
      >
        <Icon
          :icon="
            Number(item.tipo) === 1 ? 'i-lucide-wrench' : 'i-lucide-package'
          "
          class="size-4"
        />
      </span>
      <span class="text-sm tabular-nums text-n-slate-11">{{
        item.codigo
      }}</span>
      <span
        class="flex items-center flex-1 min-w-[10rem] gap-2 text-sm text-n-slate-12"
      >
        <span class="truncate" :title="item.descricao">{{
          item.descricao
        }}</span>
        <span
          v-if="Number(item.tipo) === 1"
          class="px-1.5 text-[11px] font-medium rounded shrink-0 bg-n-blue-3 text-n-blue-11"
        >
          {{ t('OUTSIDER_ERP.BUDGET.ITEMS.SERVICE') }}
        </span>
      </span>
      <input
        :value="shown(item, 'quantidade')"
        inputmode="decimal"
        :aria-label="t('OUTSIDER_ERP.BUDGET.ITEMS.QTY')"
        :disabled="readOnly"
        :class="INPUT"
        class="w-16 sm:w-full"
        @input="update(index, 'quantidade', $event.target.value)"
        @blur="normalize(index, 'quantidade')"
      />
      <input
        :value="shown(item, 'preco')"
        inputmode="decimal"
        :aria-label="t('OUTSIDER_ERP.BUDGET.ITEMS.PRICE')"
        :disabled="readOnly"
        :class="INPUT"
        class="w-28 sm:w-full"
        @input="update(index, 'preco', $event.target.value)"
        @blur="normalize(index, 'preco')"
      />
      <input
        :value="shown(item, 'desconto')"
        inputmode="decimal"
        :aria-label="t('OUTSIDER_ERP.BUDGET.ITEMS.DISCOUNT')"
        :title="
          overLimit(item)
            ? t('OUTSIDER_ERP.BUDGET.DISCOUNT.LINE_OVER', { max: discountMax })
            : undefined
        "
        :disabled="readOnly"
        :class="[INPUT, overLimit(item) && '!outline-n-ruby-9 text-n-ruby-11']"
        class="w-16 sm:w-full"
        @input="update(index, 'desconto', $event.target.value)"
        @blur="normalize(index, 'desconto')"
      />
      <strong
        class="ml-auto text-sm text-right tabular-nums sm:ml-0 text-n-slate-12"
      >
        {{ formatNumber(lineTotal(item)) }}
      </strong>
      <button
        v-if="!readOnly"
        type="button"
        class="flex items-center justify-center !p-0 rounded-md size-7 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
        :aria-label="t('OUTSIDER_ERP.BUDGET.ITEMS.REMOVE')"
        @click="remove(index)"
      >
        <Icon icon="i-lucide-trash-2" class="size-4" />
      </button>
      <span v-else />
    </div>

    <ErpProductSearch
      v-if="!readOnly"
      ref="searchRef"
      :company="props.company"
      @add="add"
    />
    <p v-if="!items.length && readOnly" class="mb-0 text-sm text-n-slate-10">
      {{ t('OUTSIDER_ERP.BUDGET.ITEMS.EMPTY') }}
    </p>
  </div>
</template>
