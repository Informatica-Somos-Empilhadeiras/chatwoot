// OUTSIDER: item do CRM no menu lateral do Chatwoot, com as seções do CRM como subitens, igual a
// Conversas e Contatos. Sem acesso ao CRM (desligado na conta, desligado para a pessoa ou fora das
// unidades) o item não aparece. O acesso é buscado aqui, fora do cálculo do menu, porque o ícone
// (que liga os avisos) só existe quando o item aparece.
import { h } from 'vue';
import CrmSidebarIcon from './components/CrmSidebarIcon.vue';
import { crmState, ensureCrmContext } from './crmStore';
import { CRM_ROUTE, crmSections } from './sections';

let contextScheduled = false;

const scheduleContext = () => {
  if (contextScheduled) return;
  contextScheduled = true;
  setTimeout(() => {
    contextScheduled = false;
    ensureCrmContext();
  });
};

export const crmSidebarItems = (t, accountScopedRoute) => {
  scheduleContext();
  if (!crmState.access.enabled) return [];
  return [
    {
      name: 'OutsiderCrm',
      label: t('OUTSIDER_CRM.SIDEBAR'),
      icon: h(CrmSidebarIcon),
      children: crmSections(crmState.access).map(section => ({
        name: `OutsiderCrm-${section.key}`,
        label: t(section.label),
        icon: section.icon,
        badgeCount: section.key === 'tasks' ? crmState.myTasks.pending : 0,
        activeOn: [CRM_ROUTE],
        to: accountScopedRoute(CRM_ROUTE, { tab: section.key }),
      })),
    },
  ];
};
