<script setup>
// OUTSIDER: desconto acima do limite das Configurações (Outsider::Erp::DiscountPolicy). Quem tem a permissão de desconto
// no Mais Prático (ou é gerente) digita o código de funcionário e a senha do ERP ali mesmo; o servidor confere no ERP e
// guarda só quem liberou. A senha sai do campo assim que a conferência termina e não fica guardada em lugar nenhum.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDate } from '../erpStore';
import { formatNumber } from './budgetHelpers';

const props = defineProps({
  discount: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  // falta salvar o que foi digitado: a conferência espera (o servidor olha o rascunho salvo)
  pending: { type: Boolean, default: false },
  readOnly: { type: Boolean, default: false },
});

const emit = defineEmits(['approve']);

const { t } = useI18n();
const code = ref('');
const password = ref('');

const percent = value => formatNumber(value, value % 1 ? 2 : 0);

const reasons = computed(() => {
  const list = [];
  if (props.discount.over_lines?.length)
    list.push(
      t('OUTSIDER_ERP.BUDGET.DISCOUNT.OVER_LINES', {
        max: percent(props.discount.line_max),
        items: props.discount.over_lines.join(', '),
      })
    );
  if (props.discount.over_total)
    list.push(
      t('OUTSIDER_ERP.BUDGET.DISCOUNT.OVER_TOTAL', {
        value: percent(props.discount.total_pct),
        max: percent(props.discount.total_max),
      })
    );
  return list;
});

const canSend = computed(
  () => /^\d{1,9}$/.test(code.value.trim()) && password.value && !props.busy
);

const approve = () => {
  if (!canSend.value) return;
  emit('approve', { code: code.value.trim(), password: password.value });
  password.value = '';
};

const INPUT =
  '!mb-0 h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
</script>

<template>
  <div
    v-if="discount.approved"
    class="flex items-center gap-2 px-3 py-2 text-sm rounded-lg bg-n-teal-2 text-n-teal-11"
  >
    <Icon icon="i-lucide-shield-check" class="size-4 shrink-0" />
    {{
      t('OUTSIDER_ERP.BUDGET.DISCOUNT.APPROVED', {
        name: discount.approved_by,
        date: formatDate(discount.approved_at),
      })
    }}
  </div>
  <form
    v-else
    class="flex flex-col gap-2 p-3 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
    autocomplete="off"
    @submit.prevent="approve"
  >
    <span class="flex items-start gap-2">
      <Icon icon="i-lucide-shield-alert" class="mt-0.5 size-4 shrink-0" />
      <span class="flex flex-col gap-0.5">
        <strong class="font-medium">
          {{ t('OUTSIDER_ERP.BUDGET.DISCOUNT.TITLE') }}
        </strong>
        <span v-for="reason in reasons" :key="reason">{{ reason }}</span>
        <span v-if="!readOnly" class="text-xs">
          {{ t('OUTSIDER_ERP.BUDGET.DISCOUNT.HINT') }}
        </span>
      </span>
    </span>
    <div v-if="!readOnly" class="flex flex-wrap items-center gap-2 pl-6">
      <input
        v-model="code"
        inputmode="numeric"
        maxlength="9"
        autocomplete="off"
        :placeholder="t('OUTSIDER_ERP.BUDGET.DISCOUNT.CODE')"
        :aria-label="t('OUTSIDER_ERP.BUDGET.DISCOUNT.CODE')"
        :class="INPUT"
        class="w-32"
      />
      <input
        v-model="password"
        type="password"
        maxlength="64"
        autocomplete="new-password"
        :placeholder="t('OUTSIDER_ERP.BUDGET.DISCOUNT.PASSWORD')"
        :aria-label="t('OUTSIDER_ERP.BUDGET.DISCOUNT.PASSWORD')"
        :class="INPUT"
        class="w-40"
      />
      <Button
        type="submit"
        size="sm"
        color="amber"
        icon="i-lucide-key-round"
        :label="t('OUTSIDER_ERP.BUDGET.DISCOUNT.APPROVE')"
        :is-loading="busy"
        :disabled="!canSend || pending"
      />
    </div>
  </form>
</template>
