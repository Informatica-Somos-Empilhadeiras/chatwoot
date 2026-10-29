<script setup>
// OUTSIDER: Telefonia > Configurações > Custos (Entrega 25; ver app/services/outsider/voice/settings_billing.rb):
// o preço por minuto e por ligação atendida de cada tipo de ligação e como a operadora conta o tempo. O
// painel calcula o custo na hora com estes valores (Outsider::Voice::CallCosts).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

defineProps({
  errors: { type: Array, default: () => [] },
});

const form = defineModel('form', { type: Object, required: true });

const { t } = useI18n();

const KINDS = [
  'local_fixed',
  'local_mobile',
  'long_fixed',
  'long_mobile',
  'international',
  'special',
  'inbound',
];

const billingOptions = computed(() =>
  ['30_6', '60_6', 'second', 'minute'].map(key => ({
    value: key,
    label: t(`OUTSIDER_VOICE.SETTINGS.COSTS.BILLINGS.${key.toUpperCase()}`),
  }))
);
</script>

<template>
  <div
    class="flex flex-col gap-1 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
  >
    <label class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_VOICE.SETTINGS.COSTS.BILLING') }}
      </span>
      <Select
        v-model="form.costs.billing"
        :options="billingOptions"
        data-testid="voice-billing"
      />
      <span class="text-xs text-n-slate-11">
        {{ t('OUTSIDER_VOICE.SETTINGS.COSTS.BILLING_HELP') }}
      </span>
    </label>
  </div>

  <div
    class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
  >
    <div
      class="flex items-center justify-between gap-3 px-4 py-2.5 text-xs font-medium border-b border-n-weak text-n-slate-11"
    >
      <span>{{ t('OUTSIDER_VOICE.SETTINGS.COSTS.KIND') }}</span>
      <span class="flex gap-3">
        <span class="w-28 text-center">
          {{ t('OUTSIDER_VOICE.SETTINGS.COSTS.MINUTE') }}
        </span>
        <span class="w-28 text-center">
          {{ t('OUTSIDER_VOICE.SETTINGS.COSTS.CALL') }}
        </span>
      </span>
    </div>
    <div
      v-for="kind in KINDS"
      :key="kind"
      class="flex flex-wrap items-center justify-between gap-3 px-4 py-2 border-b border-n-weak last:border-0"
      data-testid="voice-cost-row"
    >
      <span class="flex flex-col min-w-0">
        <span class="text-sm text-n-slate-12">
          {{ t(`OUTSIDER_VOICE.KINDS.${kind.toUpperCase()}`) }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t(`OUTSIDER_VOICE.SETTINGS.COSTS.HELP.${kind.toUpperCase()}`) }}
        </span>
      </span>
      <span class="flex gap-3">
        <Input
          v-model="form.costs.rates[kind].minute"
          inputmode="decimal"
          class="w-28"
          placeholder="0,00"
          :message-type="
            errors.includes(`costs.rates.${kind}.minute`) ? 'error' : 'info'
          "
        />
        <Input
          v-model="form.costs.rates[kind].call"
          inputmode="decimal"
          class="w-28"
          placeholder="0,00"
          :message-type="
            errors.includes(`costs.rates.${kind}.call`) ? 'error' : 'info'
          "
        />
      </span>
    </div>
  </div>
  <p class="mb-0 text-xs text-n-slate-11">
    {{ t('OUTSIDER_VOICE.SETTINGS.COSTS.NOTE') }}
  </p>
</template>
