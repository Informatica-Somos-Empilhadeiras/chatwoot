<script setup>
// OUTSIDER: itens da proposta. Cada item vem do catálogo (máquina ou acessório, com valor sugerido de
// venda ou locação) ou é livre (frete, serviço). "Características no PDF" leva a tabela e a imagem
// do catálogo para a primeira página; a proposta guarda uma cópia, então mudar o catálogo depois não
// muda proposta feita ("Atualizar do catálogo" pega os dados de agora).
// Desconto em R$ ou em % (Entrega 18): em %, o desconto em R$ é recalculado a cada mudança de
// quantidade ou valor; o que vai para o servidor e para o PDF continua em R$.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { centsToInput, formatMoney } from '../../helpers';
import {
  blankItem,
  discountPercent,
  itemTotal,
  parsePercent,
  percentDiscount,
  productItemFields,
} from './proposalHelpers';

const props = defineProps({
  kind: { type: String, required: true },
  products: { type: Array, required: true },
  readOnly: { type: Boolean, default: false },
});

const items = defineModel({ type: Array, required: true });

const MONEY_PLACEHOLDER = '0,00';
const PERCENT_PLACEHOLDER = '0';

const { t } = useI18n();

// com quantidade disponível anotada no catálogo, ela aparece na escolha do item
const productLabel = product => {
  const name = [product.code, product.name].filter(Boolean).join(' · ');
  return product.available_quantity == null
    ? name
    : t('OUTSIDER_CRM.PROPOSALS.ITEMS.PRODUCT_WITH_STOCK', {
        name,
        count: product.available_quantity,
      });
};

const productOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSALS.ITEMS.FREE_ITEM') },
  ...props.products.map(product => ({
    value: product.id,
    label: productLabel(product),
  })),
]);

const total = computed(() =>
  items.value.reduce((sum, item) => sum + (itemTotal(item) || 0), 0)
);

const add = () => {
  items.value = [...items.value, blankItem()];
};

const remove = index => {
  items.value = items.value.filter((_, position) => position !== index);
};

const move = (index, step) => {
  const list = [...items.value];
  const [item] = list.splice(index, 1);
  list.splice(index + step, 0, item);
  items.value = list;
};

// escolher um produto preenche descrição, valor sugerido e as características (máquina)
const chooseProduct = (item, productId) => {
  item.product_id = productId;
  const product = props.products.find(entry => entry.id === productId);
  if (product) Object.assign(item, productItemFields(product, props.kind));
};

const isPercent = item => item.discount_mode === 'percent';

// em %, o desconto em R$ acompanha quantidade e valor
const syncDiscount = item => {
  if (!isPercent(item)) return;
  const cents = percentDiscount(item, item.discount_percent);
  item.discount = Number.isNaN(cents) ? 'x' : centsToInput(cents);
};

const toggleMode = item => {
  if (isPercent(item)) {
    item.discount_mode = 'money';
    return;
  }
  item.discount_mode = 'percent';
  item.discount_percent = discountPercent(item) || '';
  syncDiscount(item);
};

const discountHint = item => {
  if (isPercent(item)) {
    const cents = percentDiscount(item, item.discount_percent);
    return cents && !Number.isNaN(cents)
      ? t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.AS_MONEY', {
          value: formatMoney(cents),
        })
      : '';
  }
  const percent = discountPercent(item);
  return percent
    ? t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.AS_PERCENT', { percent })
    : '';
};

// mesmo % em todos os itens; depois dá para ajustar item por item
const allPercent = ref('');
const allPercentValid = computed(
  () => allPercent.value !== '' && !Number.isNaN(parsePercent(allPercent.value))
);

const applyToAll = () => {
  if (!allPercentValid.value) return;
  items.value.forEach(item => {
    item.discount_mode = 'percent';
    item.discount_percent = allPercent.value;
    syncDiscount(item);
  });
};

const lineTotal = item => {
  const value = itemTotal(item);
  return Number.isNaN(value) ? '—' : formatMoney(value);
};

defineExpose({ add });
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-for="(item, index) in items"
      :key="index"
      class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="flex items-center justify-center text-xs font-medium rounded-full size-6 bg-n-alpha-2 text-n-slate-11 shrink-0"
        >
          {{ index + 1 }}
        </span>
        <img
          v-if="item.image_url"
          :src="item.image_url"
          alt=""
          class="object-contain rounded-md size-8 bg-n-solid-1"
        />
        <Select
          :model-value="item.product_id"
          :options="productOptions"
          :disabled="readOnly"
          class="min-w-[14rem] max-w-full [&>select]:w-full flex-1"
          @update:model-value="value => chooseProduct(item, value)"
        />
        <template v-if="!readOnly">
          <Button
            v-tooltip.top="t('OUTSIDER_CRM.PROPOSALS.ITEMS.MOVE_UP')"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-arrow-up"
            :disabled="index === 0"
            @click="move(index, -1)"
          />
          <Button
            v-tooltip.top="t('OUTSIDER_CRM.PROPOSALS.ITEMS.MOVE_DOWN')"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-arrow-down"
            :disabled="index === items.length - 1"
            @click="move(index, 1)"
          />
          <Button
            v-tooltip.top="t('OUTSIDER_CRM.PROPOSALS.ITEMS.REMOVE')"
            size="xs"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            @click="remove(index)"
          />
        </template>
      </div>
      <div
        class="grid grid-cols-2 gap-2 sm:grid-cols-[1fr_6rem_9rem_9rem_9rem]"
      >
        <label class="flex flex-col col-span-2 gap-1 text-xs sm:col-span-1">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.DESCRIPTION') }}
          </span>
          <input
            v-model="item.description"
            type="text"
            maxlength="255"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.QUANTITY') }}
          </span>
          <input
            v-model="item.quantity"
            type="text"
            inputmode="decimal"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg text-right"
            @input="syncDiscount(item)"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs">
          <span class="text-n-slate-11">
            {{
              kind === 'rental'
                ? t('OUTSIDER_CRM.PROPOSALS.ITEMS.MONTHLY_PRICE')
                : t('OUTSIDER_CRM.PROPOSALS.ITEMS.UNIT_PRICE')
            }}
          </span>
          <input
            v-model="item.unit_price"
            type="text"
            inputmode="decimal"
            :placeholder="MONEY_PLACEHOLDER"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg text-right"
            @input="syncDiscount(item)"
          />
        </label>
        <div class="flex flex-col gap-1 text-xs" data-discount>
          <span
            class="flex items-center justify-between h-4 gap-1 text-n-slate-11"
          >
            {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.LABEL') }}
            <button
              v-if="!readOnly"
              v-tooltip.top="
                t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.SWITCH')
              "
              type="button"
              class="flex overflow-hidden text-[11px] leading-[14px] rounded outline outline-1 -outline-offset-1 outline-n-weak"
              data-discount-mode
              @click="toggleMode(item)"
            >
              <span
                class="px-1.5"
                :class="
                  isPercent(item)
                    ? 'text-n-slate-10'
                    : 'bg-n-brand text-white font-medium'
                "
              >
                {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.MONEY') }}
              </span>
              <span
                class="px-1.5"
                :class="
                  isPercent(item)
                    ? 'bg-n-brand text-white font-medium'
                    : 'text-n-slate-10'
                "
              >
                {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.PERCENT') }}
              </span>
            </button>
          </span>
          <input
            v-if="isPercent(item)"
            v-model="item.discount_percent"
            type="text"
            inputmode="decimal"
            :placeholder="PERCENT_PLACEHOLDER"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg text-right"
            @input="syncDiscount(item)"
          />
          <input
            v-else
            v-model="item.discount"
            type="text"
            inputmode="decimal"
            :placeholder="MONEY_PLACEHOLDER"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg text-right"
          />
          <span class="h-3 -mt-0.5 text-[11px] text-right text-n-slate-10">
            {{ discountHint(item) }}
          </span>
        </div>
        <div class="flex flex-col gap-1 text-xs">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.TOTAL') }}
          </span>
          <span
            class="flex items-center justify-end h-10 px-2 text-sm font-medium text-n-slate-12"
            :class="{ 'text-n-ruby-11': Number.isNaN(itemTotal(item)) }"
          >
            {{ lineTotal(item) }}
          </span>
        </div>
      </div>
      <div
        v-if="item.product_id"
        class="flex flex-wrap items-center gap-4 text-xs text-n-slate-11"
      >
        <label class="flex items-center gap-2">
          <Checkbox v-model="item.show_details" :disabled="readOnly" />
          {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.SHOW_DETAILS') }}
        </label>
        <button
          v-if="!readOnly && item.id"
          type="button"
          class="text-n-blue-11 hover:underline"
          :class="{ 'font-medium': item.refresh_details }"
          @click="item.refresh_details = !item.refresh_details"
        >
          {{
            item.refresh_details
              ? t('OUTSIDER_CRM.PROPOSALS.ITEMS.REFRESH_PENDING')
              : t('OUTSIDER_CRM.PROPOSALS.ITEMS.REFRESH')
          }}
        </button>
      </div>
    </div>

    <p
      v-if="!items.length"
      class="p-4 mb-0 text-sm text-center rounded-xl text-n-slate-11 bg-n-alpha-1"
    >
      {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.EMPTY') }}
    </p>

    <div class="flex flex-wrap items-center justify-between gap-2">
      <Button
        v-if="!readOnly"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-plus"
        :label="t('OUTSIDER_CRM.PROPOSALS.ITEMS.ADD')"
        @click="add"
      />
      <span v-else />
      <div
        v-if="!readOnly && items.length > 1"
        v-tooltip.top="t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.ALL_HELP')"
        class="flex items-center gap-1.5 text-xs text-n-slate-11"
        data-discount-all
      >
        {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.ALL') }}
        <span class="relative">
          <input
            v-model="allPercent"
            type="text"
            inputmode="decimal"
            :placeholder="PERCENT_PLACEHOLDER"
            class="!mb-0 !text-sm !h-8 !w-20 !pr-6 rounded-lg text-right"
            @keydown.enter.prevent="applyToAll"
          />
          <span class="absolute -translate-y-1/2 right-2 top-1/2">%</span>
        </span>
        <Button
          size="xs"
          variant="faded"
          color="slate"
          type="button"
          :label="t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT_MODE.ALL_APPLY')"
          :disabled="!allPercentValid"
          @click="applyToAll"
        />
      </div>
      <span class="text-sm text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.GRAND_TOTAL') }}
        <strong class="ml-1 text-base text-n-slate-12">
          {{ formatMoney(total) }}
        </strong>
      </span>
    </div>
  </div>
</template>
