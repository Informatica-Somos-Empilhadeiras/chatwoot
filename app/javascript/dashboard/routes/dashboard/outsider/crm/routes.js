// OUTSIDER: CRM de vendas
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmIndex from './pages/CrmIndex.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm/:tab?'),
    name: 'outsider_crm',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: CrmIndex,
  },
];
