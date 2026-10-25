<script setup>
// OUTSIDER: ligar com 1 clique pelo telefone do CRM (Entrega 22), no contato, na conversa, no negócio e na
// fila de retorno. Só aparece para quem tem ramal; a ligação sai com o número do estado do vendedor.
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { phone, dial } from './phone';
import { formatPhone } from './format';

const props = defineProps({
  number: { type: String, default: '' },
  // o número escrito, como link (no lugar do botão só com o ícone)
  showNumber: { type: Boolean, default: false },
  label: { type: String, default: '' },
});

const { t } = useI18n();

const call = () => {
  const error = dial(props.number);
  if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
};
</script>

<template>
  <button
    v-if="phone.status !== 'off' && number && showNumber"
    type="button"
    class="inline-flex items-center gap-1 text-n-teal-11 hover:underline"
    :title="t('OUTSIDER_VOICE.CLICK_TO_CALL')"
    data-testid="outsider-click-to-call"
    @click.stop="call"
  >
    <Icon icon="i-lucide-phone-outgoing" class="size-3.5" />
    {{ formatPhone(number) }}
  </button>
  <Button
    v-else-if="phone.status !== 'off' && number"
    v-tooltip.top-end="label ? undefined : t('OUTSIDER_VOICE.CLICK_TO_CALL')"
    icon="i-lucide-phone-outgoing"
    :label="label"
    sm
    faded
    teal
    data-testid="outsider-click-to-call"
    @click.stop="call"
  />
</template>
