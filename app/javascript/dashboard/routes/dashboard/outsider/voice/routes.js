// OUTSIDER: Telefonia (Entrega 23): painel, ligações e configurações, separados do CRM
import { frontendURL } from 'dashboard/helper/URLHelper';
import VoiceIndex from './pages/VoiceIndex.vue';
import { VOICE_ROUTE } from './sections';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/telefonia/:tab?'),
    name: VOICE_ROUTE,
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: VoiceIndex,
  },
];
