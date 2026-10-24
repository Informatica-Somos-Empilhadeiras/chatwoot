<script setup>
// OUTSIDER: condição de pagamento da proposta (Entregas 19 e 20). As opções de Configurações > Propostas >
// Pagamento aparecem como botões (um clique escolhe) e o texto fica logo abaixo para ajustar. O texto vai
// para a linha de pagamento das condições (ex.: "Pagamento com recurso próprio"); quando o modelo não tem
// essa linha, ela é criada no topo das condições.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { paymentConditionIndex } from './proposalHelpers';

defineProps({
  options: { type: Array, default: () => [] },
  readOnly: { type: Boolean, default: false },
});

const conditions = defineModel({ type: Array, required: true });

const { t } = useI18n();

const index = computed(() => paymentConditionIndex(conditions.value));
const text = computed(() => conditions.value[index.value]?.text || '');

const setText = value => {
  if (index.value < 0) {
    conditions.value = [
      { label: t('OUTSIDER_CRM.PROPOSALS.PAYMENT.LABEL'), text: value },
      ...conditions.value,
    ];
    return;
  }
  conditions.value = conditions.value.map((condition, position) =>
    position === index.value ? { ...condition, text: value } : condition
  );
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div v-if="options.length" class="flex flex-wrap gap-2">
      <button
        v-for="option in options"
        :key="option"
        type="button"
        :disabled="readOnly"
        class="px-3 py-2 text-sm rounded-lg outline outline-1 -outline-offset-1 transition-colors disabled:cursor-default"
        :class="
          text.trim() === option
            ? 'bg-n-brand/10 outline-n-brand text-n-slate-12 font-medium'
            : 'outline-n-weak text-n-slate-11 enabled:hover:outline-n-slate-6 enabled:hover:text-n-slate-12'
        "
        :aria-pressed="text.trim() === option"
        @click="setText(option)"
      >
        {{ option }}
      </button>
    </div>
    <input
      :value="text"
      type="text"
      maxlength="5000"
      :disabled="readOnly"
      :placeholder="t('OUTSIDER_CRM.PROPOSALS.PAYMENT.PLACEHOLDER')"
      class="!mb-0 !text-sm rounded-lg"
      @input="setText($event.target.value)"
    />
  </div>
</template>
