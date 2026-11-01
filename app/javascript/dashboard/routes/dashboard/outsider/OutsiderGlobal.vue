<script setup>
// OUTSIDER: o que fica ativo em todas as telas do painel: avisos de transferência de conversa e a
// aparência da conta (favicon, título da aba, logo e papel de parede das conversas) e o acabamento
// das conversas no estilo WhatsApp/Telegram.
import TransferNotices from './transfer/TransferNotices.vue';
import { useAccountBranding } from './branding/useAccountBranding';
// visual das conversas no estilo WhatsApp/Telegram (balões com rabinho, modo seleção)
import 'dashboard/components-next/outsider/whatsappLook/whatsappLook.css';

useAccountBranding();
</script>

<template>
  <TransferNotices />
</template>
