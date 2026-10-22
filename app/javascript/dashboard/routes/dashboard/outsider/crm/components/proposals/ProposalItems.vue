<script setup>
// OUTSIDER: itens da proposta. Cada item vem do catálogo (máquina ou acessório, com valor sugerido de
// venda ou locação) ou é livre (frete, serviço). "Características no PDF" leva a tabela e a imagem
// do catálogo para a primeira página; a proposta guarda uma cópia, então mudar o catálogo depois não
// muda proposta feita ("Atualizar do catálogo" pega os dados de agora).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { centsToInput, formatMoney } from '../../helpers';
import { itemTotal } from './proposalHelpers';

const props = defineProps({
  kind: { type: String, required: true },
  products: { type: Array, required: true },
  readOnly: { type: Boolean, default: false },
});

const items = defineModel({ type: Array, required: true });

const MONEY_PLACEHOLDER = '0,00';

const { t } = useI18n();

const productOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSALS.ITEMS.FREE_ITEM') },
  ...props.products.map(product => ({
    value: product.id,
    label: [product.code, product.name].filter(Boolean).join(' · '),
  })),
]);

const total = computed(() =>
  items.value.reduce((sum, item) => sum + (itemTotal(item) || 0), 0)
);

const suggestedPrice = product =>
  props.kind === 'rental'
    ? product.rental_price_cents
    : product.sale_price_cents;

const blankItem = () => ({
  id: null,
  product_id: '',
  description: '',
  quantity: '1',
  unit_price: '',
  discount: '',
  show_details: false,
  refresh_details: false,
  image_url: null,
});

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
  if (!product) return;
  item.description = product.name;
  item.unit_price = centsToInput(suggestedPrice(product));
  item.show_details = product.kind === 'machine';
  item.image_url = product.image_url;
  item.refresh_details = true;
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
          />
        </label>
        <label class="flex flex-col gap-1 text-xs">
          <span class="text-n-slate-11">
            {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.DISCOUNT') }}
          </span>
          <input
            v-model="item.discount"
            type="text"
            inputmode="decimal"
            :placeholder="MONEY_PLACEHOLDER"
            :disabled="readOnly"
            class="!mb-0 !text-sm rounded-lg text-right"
          />
        </label>
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
      <span class="text-sm text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSALS.ITEMS.GRAND_TOTAL') }}
        <strong class="ml-1 text-base text-n-slate-12">
          {{ formatMoney(total) }}
        </strong>
      </span>
    </div>
  </div>
</template>
