<script setup>
// OUTSIDER: o que fica ativo em todas as telas do painel: avisos de transferência de conversa e a
// aparência da conta (favicon, título da aba, logo e papel de parede das conversas).
import TransferNotices from './transfer/TransferNotices.vue';
import { useAccountBranding } from './branding/useAccountBranding';

useAccountBranding();
</script>

<template>
  <TransferNotices />
</template>
