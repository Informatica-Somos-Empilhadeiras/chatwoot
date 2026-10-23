<script setup>
// OUTSIDER: condições da proposta (pagamento, frete, prazo, garantia...). Vêm do modelo e mudam só
// nesta proposta. Aceitam **negrito** e campos automáticos como {proposta.validade}.
// Condição de pagamento (Entrega 19): escolher uma das opções de Configurações > Propostas > Pagamento
// troca o texto da linha de pagamento (ou cria a linha no topo, quando o modelo não tem). O texto
// continua editável na própria linha.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { paymentConditionIndex } from './proposalHelpers';

const props = defineProps({
  readOnly: { type: Boolean, default: false },
  paymentOptions: { type: Array, default: () => [] },
});

const conditions = defineModel({ type: Array, required: true });

const { t } = useI18n();

// texto da linha de pagamento que não é nenhuma das opções
const CUSTOM_PAYMENT = '__custom__';

const paymentIndex = computed(() => paymentConditionIndex(conditions.value));

const paymentValue = computed(() => {
  const text = conditions.value[paymentIndex.value]?.text?.trim() || '';
  if (!text) return '';
  return props.paymentOptions.includes(text) ? text : CUSTOM_PAYMENT;
});

const paymentSelectOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSALS.PAYMENT.CHOOSE') },
  ...props.paymentOptions.map(option => ({ value: option, label: option })),
  ...(paymentValue.value === CUSTOM_PAYMENT
    ? [
        {
          value: CUSTOM_PAYMENT,
          label: t('OUTSIDER_CRM.PROPOSALS.PAYMENT.CUSTOM'),
        },
      ]
    : []),
]);

const choosePayment = option => {
  if (!option || option === CUSTOM_PAYMENT) return;
  const index = paymentIndex.value;
  conditions.value =
    index < 0
      ? [
          { label: t('OUTSIDER_CRM.PROPOSALS.PAYMENT.LABEL'), text: option },
          ...conditions.value,
        ]
      : conditions.value.map((condition, position) =>
          position === index ? { ...condition, text: option } : condition
        );
};

const add = () => {
  conditions.value = [...conditions.value, { label: '', text: '' }];
};

const remove = index => {
  conditions.value = conditions.value.filter(
    (_, position) => position !== index
  );
};

const move = (index, step) => {
  const list = [...conditions.value];
  const [condition] = list.splice(index, 1);
  list.splice(index + step, 0, condition);
  conditions.value = list;
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <label
      v-if="paymentOptions.length"
      class="flex flex-wrap items-center gap-2 pb-2 mb-1 text-sm border-b border-n-weak"
    >
      <span class="font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSALS.PAYMENT.LABEL') }}
      </span>
      <Select
        :model-value="paymentValue"
        :options="paymentSelectOptions"
        :disabled="readOnly"
        class="min-w-[16rem] [&>select]:w-full"
        @update:model-value="choosePayment"
      />
      <span class="text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSALS.PAYMENT.HELP') }}
      </span>
    </label>
    <div
      v-for="(condition, index) in conditions"
      :key="index"
      class="grid gap-2 sm:grid-cols-[14rem_1fr_auto] items-start"
    >
      <input
        v-model="condition.label"
        type="text"
        maxlength="120"
        :disabled="readOnly"
        :placeholder="t('OUTSIDER_CRM.PROPOSALS.CONDITIONS.LABEL')"
        class="!mb-0 !text-sm rounded-lg font-medium"
      />
      <textarea
        v-model="condition.text"
        rows="2"
        maxlength="5000"
        :disabled="readOnly"
        :placeholder="t('OUTSIDER_CRM.PROPOSALS.CONDITIONS.TEXT')"
        class="!mb-0 !text-sm rounded-lg"
      />
      <div v-if="!readOnly" class="flex items-center gap-1 sm:pt-1">
        <Button
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-arrow-up"
          :disabled="index === 0"
          @click="move(index, -1)"
        />
        <Button
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-arrow-down"
          :disabled="index === conditions.length - 1"
          @click="move(index, 1)"
        />
        <Button
          size="xs"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          @click="remove(index)"
        />
      </div>
    </div>
    <p
      v-if="!conditions.length"
      class="p-4 mb-0 text-sm text-center rounded-xl text-n-slate-11 bg-n-alpha-1"
    >
      {{ t('OUTSIDER_CRM.PROPOSALS.CONDITIONS.EMPTY') }}
    </p>
    <div v-if="!readOnly">
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-plus"
        :label="t('OUTSIDER_CRM.PROPOSALS.CONDITIONS.ADD')"
        @click="add"
      />
    </div>
  </div>
</template>
