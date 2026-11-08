// OUTSIDER: páginas do Somos em Configurações, só para administradores: Aparência (favicon, título,
// logo e fundo da conta) e Automação por bot (lista de fluxos e o editor de fluxograma, em tela cheia).
// Entrega 26: Microsoft Teams (robôs do Teams ligados a caixas de entrada).
// "Conectar meu Teams": a tela do Teams vale para todos (cada um conecta o próprio; a parte da empresa
// só aparece para administradores) e a área Teams do menu (chats e canais de quem conectou).
// Notificações: o aviso novo (push) que substitui o do Chatwoot no navegador; vale para todos.
import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from 'dashboard/routes/dashboard/settings/SettingsWrapper.vue';
import BrandingSettings from '../branding/BrandingSettings.vue';
import BotFlowsIndex from '../bot/BotFlowsIndex.vue';
import BotFlowEditor from '../bot/BotFlowEditor.vue';
import TeamsSettings from '../teams/TeamsSettings.vue';
import TeamsArea from '../teams/TeamsArea.vue';
import PushSettings from '../push/PushSettings.vue';

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
      {
        path: 'teams',
        name: 'outsider_teams_settings',
        component: TeamsSettings,
        meta: { permissions: ['administrator', 'agent'] },
      },
      // aviso novo no navegador e no celular (cada pessoa escolhe o que recebe)
      {
        path: 'notifications',
        name: 'outsider_push_settings',
        component: PushSettings,
        meta: { permissions: ['administrator', 'agent'] },
      },
    ],
  },
  {
    path: frontendURL('accounts/:accountId/settings/outsider/bots/:flowId'),
    name: 'outsider_bot_flow_editor',
    component: BotFlowEditor,
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/teams/:kind(chats|channels)?/:threadId?'
    ),
    name: 'outsider_teams',
    component: TeamsArea,
    meta: { permissions: ['administrator', 'agent'] },
  },
];
