// OUTSIDER: menu "ERP" no menu lateral (secao Atendimento) com uma aba por modulo: Orcamentos, OS, Pedidos e, para o
// administrador, as Configuracoes. Some sem a tela ERP no perfil de acesso; com a integracao desligada so o admin ve.
import { allows } from '../access/accessStore';
import { erpState, ERP_ROUTE } from './erpStore';

export const erpSidebarItems = (t, accountScopedRoute) => {
  if (!erpState.loaded || !allows('erp')) return [];
  if (!erpState.enabled && !erpState.administrator) return [];

  const tab = (name, label, icon) => ({
    name: `OutsiderErp-${name}`,
    label: t(label),
    icon,
    activeOn: [ERP_ROUTE],
    to: accountScopedRoute(ERP_ROUTE, { tab: name }),
  });

  const children = [];
  if (erpState.enabled && erpState.quotesEnabled) {
    children.push(tab('orcamentos', 'OUTSIDER_ERP.TABS.ORCAMENTOS', 'i-lucide-file-text'));
  }
  if (erpState.enabled && erpState.ordersEnabled) {
    children.push(tab('os', 'OUTSIDER_ERP.TABS.OS', 'i-lucide-kanban'));
  }
  if (erpState.enabled) {
    children.push(tab('pedidos', 'OUTSIDER_ERP.TABS.PEDIDOS', 'i-lucide-shopping-cart'));
  }
  if (erpState.administrator) {
    children.push(tab('settings', 'OUTSIDER_ERP.TABS.SETTINGS', 'i-lucide-settings-2'));
  }
  if (!children.length) return [];

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
