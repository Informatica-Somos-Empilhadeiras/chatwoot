// OUTSIDER: seção Relatórios de gestão (gestao/:report), um relatório por aba (reportsCatalog.js)
import { frontendURL } from 'dashboard/helper/URLHelper';
import ReportsIndex from './pages/ReportsIndex.vue';
import { REPORTS_ROUTE } from './reportsCatalog';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/gestao/:report?'),
    name: REPORTS_ROUTE,
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: ReportsIndex,
  },
];
