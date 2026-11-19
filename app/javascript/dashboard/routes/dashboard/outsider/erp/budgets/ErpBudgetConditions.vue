<script setup>
// OUTSIDER: condições do orçamento (pagamento, gênero, frete, vendedor, prazos e observações) e o quadro de totais. Já
// vêm com o padrão das Configurações; "Mais condições" abre o resto das "Demais Condições" do Mais Prático.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatMoney } from '../erpStore';
import { budgetTotals } from './budgetHelpers';

const props = defineProps({
  items: { type: Array, default: () => [] },
  options: { type: Object, default: () => ({}) },
  readOnly: { type: Boolean, default: false },
});

const terms = defineModel({ type: Object, default: () => ({}) });

const { t } = useI18n();
const MORE = [
  'reajuste',
  'icms',
  'ipi',
  'desc_frete',
  'armazenagem',
  'cancelamento',
];
const more = ref(
  MORE.some(key => terms.value[key]) || Number(terms.value.frete_valor) > 0
);

const set = (key, value) => {
  terms.value = { ...terms.value, [key]: value };
};

// a escolha gravada entra na lista mesmo se o ERP não a devolver (lista fora do ar ou código antigo)
const withCurrent = (list, value, label) => {
  const current = Number(value || 0);
  if (!current || list.some(item => item.codigo === current)) return list;
  return [{ codigo: current, descricao: label }, ...list];
};

const payments = computed(() =>
  withCurrent(
    props.options.payment_terms || [],
    terms.value.forma_pagto,
    t('OUTSIDER_ERP.BUDGET.TERMS.CODE', { code: terms.value.forma_pagto })
  )
);
const sellers = computed(() =>
  withCurrent(
    (props.options.sellers || []).map(item => ({
      codigo: item.codigo,
      descricao: item.nome,
    })),
    terms.value.vendedor,
    t('OUTSIDER_ERP.BUDGET.TERMS.CODE', { code: terms.value.vendedor })
  )
);

const totals = computed(() =>
  budgetTotals(props.items, terms.value.frete_valor)
);

const SELECTS = computed(() => [
  { key: 'forma_pagto', list: payments.value, pick: true },
  { key: 'genero', list: props.options.generos || [] },
  { key: 'tipo_frete', list: props.options.fretes || [] },
  { key: 'vendedor', list: sellers.value, pick: true },
]);

const INPUT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand disabled:opacity-70';
const LABEL =
  'flex flex-col gap-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10';
</script>

<template>
  <div class="flex flex-col gap-4 lg:flex-row lg:items-start">
    <div class="flex flex-col flex-1 min-w-0 gap-3">
      <h4 class="mb-0 text-base font-medium text-n-slate-12">
        {{ t('OUTSIDER_ERP.BUDGET.TERMS.TITLE') }}
        <span class="text-xs font-normal text-n-slate-10">
          · {{ t('OUTSIDER_ERP.BUDGET.TERMS.DEFAULTS') }}
        </span>
      </h4>
      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <label v-for="field in SELECTS" :key="field.key" :class="LABEL">
          {{ t(`OUTSIDER_ERP.BUDGET.TERMS.${field.key.toUpperCase()}`) }}
          <select
            v-if="field.list.length"
            :value="terms[field.key] ?? (field.pick ? 0 : '')"
            :disabled="readOnly"
            :class="INPUT"
            class="normal-case !pr-7 bg-[right_-1.25rem_center]"
            @change="set(field.key, Number($event.target.value))"
          >
            <option v-if="field.pick" :value="0">
              {{ t('OUTSIDER_ERP.BUDGET.TERMS.PICK') }}
            </option>
            <option
              v-for="item in field.list"
              :key="item.codigo"
              :value="item.codigo"
            >
              {{ item.descricao || item.codigo }}
            </option>
          </select>
          <input
            v-else
            :value="terms[field.key]"
            type="number"
            min="0"
            :disabled="readOnly"
            :placeholder="t('OUTSIDER_ERP.BUDGET.TERMS.CODE_PLACEHOLDER')"
            :class="INPUT"
            class="normal-case"
            @input="set(field.key, Number($event.target.value) || null)"
          />
        </label>
      </div>

      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <label
          v-for="key in ['prazo_entrega', 'validade', 'garantia']"
          :key="key"
          :class="LABEL"
        >
          {{ t(`OUTSIDER_ERP.BUDGET.TERMS.${key.toUpperCase()}`) }}
          <input
            :value="terms[key]"
            :disabled="readOnly"
            maxlength="255"
            :class="INPUT"
            class="normal-case"
            @input="set(key, $event.target.value)"
          />
        </label>
        <button
          v-if="!more"
          type="button"
          class="flex items-center self-end gap-1 h-9 text-sm font-medium text-n-brand hover:underline"
          @click="more = true"
        >
          <Icon icon="i-lucide-plus" class="size-4" />
          {{ t('OUTSIDER_ERP.BUDGET.TERMS.MORE') }}
        </button>
      </div>

      <div v-if="more" class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <label v-for="key in MORE" :key="key" :class="LABEL">
          {{ t(`OUTSIDER_ERP.BUDGET.TERMS.${key.toUpperCase()}`) }}
          <input
            :value="terms[key]"
            :disabled="readOnly"
            :maxlength="key === 'desc_frete' ? 150 : 255"
            :class="INPUT"
            class="normal-case"
            @input="set(key, $event.target.value)"
          />
        </label>
        <label :class="LABEL">
          {{ t('OUTSIDER_ERP.BUDGET.TERMS.FRETE_VALOR') }}
          <input
            :value="terms.frete_valor"
            inputmode="decimal"
            :disabled="readOnly"
            :class="INPUT"
            class="text-right normal-case"
            @input="set('frete_valor', $event.target.value)"
          />
        </label>
      </div>

      <label :class="LABEL">
        {{ t('OUTSIDER_ERP.BUDGET.TERMS.OBSERVACOES') }}
        <textarea
          :value="terms.observacoes"
          rows="2"
          maxlength="2000"
          :disabled="readOnly"
          class="!mb-0 w-full px-2.5 py-2 text-sm normal-case rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand disabled:opacity-70"
          @input="set('observacoes', $event.target.value)"
        />
      </label>
    </div>

    <aside
      class="flex flex-col gap-1.5 p-4 text-sm border lg:w-72 shrink-0 rounded-xl border-n-weak bg-n-alpha-1"
    >
      <div class="flex justify-between text-n-slate-11">
        <span>{{ t('OUTSIDER_ERP.BUDGET.TOTALS.PARTS') }}</span>
        <span class="tabular-nums">{{ formatMoney(totals.parts) }}</span>
      </div>
      <div class="flex justify-between text-n-slate-11">
        <span>{{ t('OUTSIDER_ERP.BUDGET.TOTALS.SERVICES') }}</span>
        <span class="tabular-nums">{{ formatMoney(totals.services) }}</span>
      </div>
      <div v-if="totals.discounts" class="flex justify-between text-n-slate-11">
        <span>{{ t('OUTSIDER_ERP.BUDGET.TOTALS.DISCOUNTS') }}</span>
        <span class="tabular-nums text-n-ruby-11">
          − {{ formatMoney(totals.discounts) }}
        </span>
      </div>
      <div v-if="totals.freight" class="flex justify-between text-n-slate-11">
        <span>{{ t('OUTSIDER_ERP.BUDGET.TOTALS.FREIGHT') }}</span>
        <span class="tabular-nums">{{ formatMoney(totals.freight) }}</span>
      </div>
      <div
        class="flex items-baseline justify-between pt-2 mt-1 border-t border-n-weak"
      >
        <strong class="text-n-slate-12">{{
          t('OUTSIDER_ERP.BUDGET.TOTALS.TOTAL')
        }}</strong>
        <strong class="text-lg tabular-nums text-n-slate-12">
          {{ formatMoney(totals.total) }}
        </strong>
      </div>
      <p class="mt-1 mb-0 text-xs text-n-slate-10">
        {{ t('OUTSIDER_ERP.BUDGET.TOTALS.TAXES') }}
      </p>
    </aside>
  </div>
</template>
