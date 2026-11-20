// OUTSIDER: pagina da secao ERP (Mais Pratico) - abas Orcamentos, OS, Pedidos e Configuracoes (erp/:tab)
import { frontendURL } from 'dashboard/helper/URLHelper';
import ErpIndex from './pages/ErpIndex.vue';
import { ERP_ROUTE } from './erpStore';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/erp/:tab?'),
    name: ERP_ROUTE,
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: ErpIndex,
  },
];
