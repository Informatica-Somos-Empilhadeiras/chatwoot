<script setup>
// OUTSIDER: selo com o valor em aberto do contato no CRM, nos cards da lista de conversas.
// Os cards visíveis pedem juntos (crmStore agrupa os pedidos); some se não houver negócio aberto.
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { crmState, requestContactChip } from '../crmStore';
import { formatMoney } from '../helpers';

const props = defineProps({
  contactId: { type: Number, default: null },
});

const { t } = useI18n();

const chip = computed(() =>
  crmState.access.enabled ? crmState.chips[props.contactId] : null
);

// access.enabled: o CRM religado com a lista aberta pede os selos na hora
watch(
  () => [props.contactId, crmState.access.enabled],
  () => requestContactChip(props.contactId),
  { immediate: true }
);
</script>

<template>
  <span
    v-if="chip"
    v-tooltip="
      t('OUTSIDER_CRM.CONVERSATION.CHIP_TOOLTIP', { count: chip.open_count })
    "
    class="inline-flex items-center gap-1 px-1.5 py-px text-xs font-medium rounded-md bg-n-teal-3 text-n-teal-11"
  >
    <Icon icon="i-lucide-handshake" class="size-3" />
    {{ formatMoney(chip.open_value_cents) }}
  </span>
</template>
