// OUTSIDER: páginas do Somos em Configurações, só para administradores: Aparência (favicon, título,
// logo e fundo da conta) e Automação por bot (lista de fluxos e o editor de fluxograma, em tela cheia).
import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from 'dashboard/routes/dashboard/settings/SettingsWrapper.vue';
import BrandingSettings from '../branding/BrandingSettings.vue';
import BotFlowsIndex from '../bot/BotFlowsIndex.vue';
import BotFlowEditor from '../bot/BotFlowEditor.vue';

const meta = { permissions: ['administrator'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/outsider'),
    component: SettingsWrapper,
    props: { keepAlive: false },
    children: [
      {
        path: 'appearance',
        name: 'outsider_branding_settings',
        component: BrandingSettings,
        meta,
      },
      {
        path: 'bots',
        name: 'outsider_bot_flows',
        component: BotFlowsIndex,
        meta,
      },
    ],
  },
  {
    path: frontendURL('accounts/:accountId/settings/outsider/bots/:flowId'),
    name: 'outsider_bot_flow_editor',
    component: BotFlowEditor,
    meta,
  },
];
