<script setup>
// OUTSIDER: condições da proposta (pagamento, frete, prazo, garantia...). Vêm do modelo e mudam só
// nesta proposta. Aceitam **negrito** e campos automáticos como {proposta.validade}.
// A condição de pagamento escolhida da lista fica em PaymentPicker (Entregas 19 e 20).
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  readOnly: { type: Boolean, default: false },
});

const conditions = defineModel({ type: Array, required: true });

const { t } = useI18n();

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
