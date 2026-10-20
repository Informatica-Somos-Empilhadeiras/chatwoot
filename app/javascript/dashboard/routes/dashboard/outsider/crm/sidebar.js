// OUTSIDER: item do CRM no menu lateral do Chatwoot, com as seções do CRM como subitens, igual a
// Conversas e Contatos. Sem acesso ao CRM (ou antes de saber), fica só o link, como antes.
import { h } from 'vue';
import CrmSidebarIcon from './components/CrmSidebarIcon.vue';
import { crmState } from './crmStore';
import { CRM_ROUTE, crmSections } from './sections';

export const crmSidebarItem = (t, accountScopedRoute) => {
  const item = {
    name: 'OutsiderCrm',
    label: t('OUTSIDER_CRM.SIDEBAR'),
    icon: h(CrmSidebarIcon),
  };
  if (!crmState.access.enabled) {
    return { ...item, to: accountScopedRoute(CRM_ROUTE) };
  }
  return {
    ...item,
    children: crmSections(crmState.access).map(section => ({
      name: `OutsiderCrm-${section.key}`,
      label: t(section.label),
      icon: section.icon,
      badgeCount: section.key === 'tasks' ? crmState.myTasks.pending : 0,
      activeOn: [CRM_ROUTE],
      to: accountScopedRoute(CRM_ROUTE, { tab: section.key }),
    })),
  };
};
