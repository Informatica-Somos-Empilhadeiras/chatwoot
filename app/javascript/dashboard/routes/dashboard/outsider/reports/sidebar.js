// OUTSIDER: menu "Relatórios de gestão" no menu lateral, um item por relatório liberado no perfil de acesso
import { openReports, REPORTS_ROUTE } from './reportsCatalog';

export const reportsSidebarItems = (t, accountScopedRoute) => {
  const children = openReports().map(report => ({
    name: `OutsiderReports-${report.key}`,
    label: t(report.label),
    icon: report.icon,
    activeOn: [REPORTS_ROUTE],
    to: accountScopedRoute(REPORTS_ROUTE, { report: report.key }),
  }));
  if (!children.length) return [];

  return [
    {
      name: 'OutsiderReports',
      label: t('OUTSIDER_REPORTS.SIDEBAR'),
      icon: 'i-lucide-chart-column-big',
      children,
    },
  ];
};
