<script setup>
// OUTSIDER: o que fica ativo em todas as telas do painel: avisos de transferência de conversa e a
// aparência da conta (favicon, título da aba, logo e papel de parede das conversas) e o acabamento
// das conversas no estilo WhatsApp/Telegram e o ajuste para celular e tablet.
import TransferNotices from './transfer/TransferNotices.vue';
// visualizador de documentos (PDF, Word, Excel, PowerPoint) dentro do Chatwoot
import FileViewer from 'dashboard/components-next/outsider/fileViewer/FileViewer.vue';
// aviso novo (push): pede para ativar neste aparelho e abre a conversa ao clicar no aviso
import PushBanner from './push/PushBanner.vue';
import { useAccountBranding } from './branding/useAccountBranding';
// item Teams do menu e as não lidas (só para quem conectou o próprio Teams)
import { watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { startTeamsUpdates } from './teams/teamsStore';
// visual das conversas no estilo WhatsApp/Telegram (balões com rabinho, modo seleção)
import 'dashboard/components-next/outsider/whatsappLook/whatsappLook.css';
// celular e tablet: altura real da tela com o teclado, painel do contato e arrastar no toque
import { useOutsiderResponsive } from './responsive/useOutsiderResponsive';
import './responsive/responsive.css';
// cores da identidade visual da Somos Empilhadeiras
import './responsive/brand.css';

useAccountBranding();
useOutsiderResponsive();

const currentAccountId = useMapGetter('getCurrentAccountId');
watch(currentAccountId, id => id && startTeamsUpdates(id), { immediate: true });
</script>

<template>
  <TransferNotices />
  <FileViewer />
  <PushBanner />
</template>
