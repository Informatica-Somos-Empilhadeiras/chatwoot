// OUTSIDER: página Status do WhatsApp
import { frontendURL } from 'dashboard/helper/URLHelper';
import WhatsappStatusIndex from './pages/WhatsappStatusIndex.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/whatsapp-status'),
    name: 'outsider_whatsapp_status',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: WhatsappStatusIndex,
  },
];
