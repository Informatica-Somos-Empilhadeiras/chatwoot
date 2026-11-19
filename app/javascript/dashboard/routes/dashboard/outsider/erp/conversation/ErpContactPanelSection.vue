<script setup>
// OUTSIDER: bloco "ERP" no painel do contato dentro da conversa: as ordens de serviço e os orçamentos do cliente no ERP
// Mais Prático (some com a integração desligada ou sem a tela ERP no perfil de acesso).
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ErpContactOrders from '../components/ErpContactOrders.vue';
import { erpState } from '../erpStore';

defineProps({
  contactId: { type: Number, default: null },
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const { isContactSidebarItemOpen, toggleSidebarUIState } = useUISettings();
</script>

<template>
  <AccordionItem
    v-if="erpState.enabled && contactId"
    :title="t('OUTSIDER_ERP.CONTACT.PANEL_TITLE')"
    :is-open="isContactSidebarItemOpen('is_outsider_erp_open')"
    compact
    @toggle="value => toggleSidebarUIState('is_outsider_erp_open', value)"
  >
    <div class="px-2 pb-1">
      <ErpContactOrders
        v-if="isContactSidebarItemOpen('is_outsider_erp_open')"
        :contact-id="contactId"
        :conversation-id="conversationId"
      />
    </div>
  </AccordionItem>
</template>
