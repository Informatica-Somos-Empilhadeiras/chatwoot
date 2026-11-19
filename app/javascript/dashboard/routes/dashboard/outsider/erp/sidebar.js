// OUTSIDER: item Ordens de serviço no menu lateral (seção Atendimento), com o quadro e, para administradores, as
// Configurações. Some sem a tela ERP no perfil de acesso; com a integração desligada só o administrador vê (para ligar).
// Com as OS ocultas ("Mostrar ordens de serviço" desligado) sai o quadro e o item vira "ERP", só do administrador.
import { allows } from '../access/accessStore';
import { erpState, ERP_ROUTE } from './erpStore';

export const erpSidebarItems = (t, accountScopedRoute) => {
  if (!erpState.loaded || !allows('erp')) return [];
  if (!erpState.enabled && !erpState.administrator) return [];
  const showOrders = !erpState.enabled || erpState.ordersEnabled;
  const children = [];
  if (showOrders) {
    children.push({
      name: 'OutsiderErp-board',
      label: t('OUTSIDER_ERP.TABS.BOARD'),
      icon: 'i-lucide-kanban',
      activeOn: [ERP_ROUTE],
      to: accountScopedRoute(ERP_ROUTE, { tab: 'board' }),
    });
  }
  if (erpState.administrator) {
    children.push({
      name: 'OutsiderErp-settings',
      label: t('OUTSIDER_ERP.TABS.SETTINGS'),
      icon: 'i-lucide-settings-2',
      activeOn: [ERP_ROUTE],
      to: accountScopedRoute(ERP_ROUTE, { tab: 'settings' }),
    });
  }
  if (!children.length) return [];
  return [
    {
      name: 'OutsiderErp',
      label: t(
        showOrders ? 'OUTSIDER_ERP.SIDEBAR' : 'OUTSIDER_ERP.SIDEBAR_QUOTES'
      ),
      icon: 'i-lucide-clipboard-list',
      navSection: 'atendimento',
      children,
    },
  ];
};
