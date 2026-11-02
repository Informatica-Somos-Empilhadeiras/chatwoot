// OUTSIDER: Telefonia (Entrega 23): painel, ligações e configurações, separados do CRM. Entrega 26: o editor
// da URA em tela cheia (só administradores; a lista fica na seção URA).
import { frontendURL } from 'dashboard/helper/URLHelper';
import VoiceIndex from './pages/VoiceIndex.vue';
import IvrFlowEditor from './ivr/IvrFlowEditor.vue';
import { VOICE_ROUTE } from './sections';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/telefonia/ura/:flowId'),
    name: 'outsider_voice_ivr_editor',
    meta: {
      permissions: ['administrator'],
    },
    component: IvrFlowEditor,
  },
  {
    path: frontendURL('accounts/:accountId/telefonia/:tab?'),
    name: VOICE_ROUTE,
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: VoiceIndex,
  },
];
