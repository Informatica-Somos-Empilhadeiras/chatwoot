// OUTSIDER: item Ordens de serviço no menu lateral (seção Atendimento), com o quadro e, para administradores, as
// Configurações. Some sem a tela ERP no perfil de acesso; com a integração desligada só o administrador vê (para ligar).
import { allows } from '../access/accessStore';
import { erpState, ERP_ROUTE } from './erpStore';

export const erpSidebarItems = (t, accountScopedRoute) => {
  if (!erpState.loaded || !allows('erp')) return [];
  if (!erpState.enabled && !erpState.administrator) return [];
  const children = [
    {
      name: 'OutsiderErp-board',
      label: t('OUTSIDER_ERP.TABS.BOARD'),
      icon: 'i-lucide-kanban',
      activeOn: [ERP_ROUTE],
      to: accountScopedRoute(ERP_ROUTE, { tab: 'board' }),
    },
  ];
  if (erpState.administrator) {
    children.push({
      name: 'OutsiderErp-settings',
      label: t('OUTSIDER_ERP.TABS.SETTINGS'),
      icon: 'i-lucide-settings-2',
      activeOn: [ERP_ROUTE],
      to: accountScopedRoute(ERP_ROUTE, { tab: 'settings' }),
    });
  }
  return [
    {
      name: 'OutsiderErp',
      label: t('OUTSIDER_ERP.SIDEBAR'),
      icon: 'i-lucide-clipboard-list',
      navSection: 'atendimento',
      children,
    },
  ];
};
