// OUTSIDER: os relatórios da seção ERP. Cada um é uma aba (erp/relatorio-<chave>), separada das abas dos módulos, com
// a linha dele no perfil de acesso (screen, abaixo da tela "reports") e a condição para aparecer. Relatório novo: uma
// entrada aqui, o componente e o controlador em app/controllers/api/v1/accounts/outsider/reports/.
import { defineAsyncComponent } from 'vue';
import { allows } from '../access/accessStore';
import { erpState } from '../erp/erpStore';

export const REPORTS = [
  {
    key: 'tecnicos',
    screen: 'reports_technicians',
    label: 'OUTSIDER_REPORTS.TECHNICIANS.TAB',
    icon: 'i-lucide-hard-hat',
    available: () => erpState.enabled,
    component: defineAsyncComponent(
      () => import('./technicians/TechnicianReport.vue')
    ),
  },
];

// os relatórios que a pessoa abre agora, como abas da seção ERP (na ordem do menu)
export const reportTabs = () => {
  if (!allows('reports')) return [];
  return REPORTS.filter(
    report => allows(report.screen) && report.available()
  ).map(report => ({
    name: `relatorio-${report.key}`,
    label: report.label,
    icon: report.icon,
    report,
  }));
};
