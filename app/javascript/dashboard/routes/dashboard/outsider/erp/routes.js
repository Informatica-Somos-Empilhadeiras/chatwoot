// OUTSIDER: página Ordens de serviço (ERP Mais Prático)
import { frontendURL } from 'dashboard/helper/URLHelper';
import ErpIndex from './pages/ErpIndex.vue';
import { ERP_ROUTE } from './erpStore';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ordens-servico/:tab?'),
    name: ERP_ROUTE,
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: ErpIndex,
  },
];
