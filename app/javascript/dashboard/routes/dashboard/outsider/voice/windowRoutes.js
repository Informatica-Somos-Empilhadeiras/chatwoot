// OUTSIDER: o telefone na janela própria (Entrega 24): fora da tela do Chatwoot (sem o menu lateral)
import { frontendURL } from 'dashboard/helper/URLHelper';
import PhoneWindow from './pages/PhoneWindow.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/telefone'),
    name: 'outsider_phone_window',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: PhoneWindow,
  },
];
