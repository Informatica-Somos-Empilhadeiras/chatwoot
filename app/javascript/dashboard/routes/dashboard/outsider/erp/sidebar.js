// OUTSIDER: menu "ERP" no menu lateral (secao Atendimento) com uma aba por modulo: Orcamentos, OS, Pedidos, Notas fiscais,
// Produtos (consulta, com as fotos) e, para o administrador, as Configuracoes. Cada aba segue o que esta ligado nas Configuracoes e a linha dela no perfil
// de acesso (erp_quotes, erp_orders, erp_sales, erp_invoices, erp_products, abaixo da tela "erp"); com a integracao desligada so o admin ve.
import { allows } from '../access/accessStore';
import { erpState, ERP_ROUTE } from './erpStore';

export const ERP_TABS = [
  {
    name: 'orcamentos',
    label: 'OUTSIDER_ERP.TABS.ORCAMENTOS',
    icon: 'i-lucide-file-text',
  },
  { name: 'os', label: 'OUTSIDER_ERP.TABS.OS', icon: 'i-lucide-wrench' },
  {
    name: 'pedidos',
    label: 'OUTSIDER_ERP.TABS.PEDIDOS',
    icon: 'i-lucide-shopping-cart',
  },
  {
    name: 'notas',
    label: 'OUTSIDER_ERP.TABS.NOTAS',
    icon: 'i-lucide-receipt-text',
  },
  {
    name: 'produtos',
    label: 'OUTSIDER_ERP.TABS.PRODUTOS',
    icon: 'i-lucide-package-search',
  },
  {
    name: 'settings',
    label: 'OUTSIDER_ERP.TABS.SETTINGS',
    icon: 'i-lucide-settings-2',
  },
];

// abas que a pessoa abre agora (a ordem do menu)
export const erpTabs = () => {
  if (!erpState.loaded || !allows('erp')) return [];
  const open = {
    orcamentos:
      erpState.enabled && erpState.quotesEnabled && allows('erp_quotes'),
    os: erpState.enabled && erpState.ordersEnabled && allows('erp_orders'),
    pedidos: erpState.enabled && allows('erp_sales'),
    notas: erpState.enabled && allows('erp_invoices'),
    produtos: erpState.enabled && allows('erp_products'),
    settings: erpState.administrator,
  };
  return ERP_TABS.filter(tab => open[tab.name]);
};

export const erpSidebarItems = (t, accountScopedRoute) => {
  const children = erpTabs().map(tab => ({
    name: `OutsiderErp-${tab.name}`,
    label: t(tab.label),
    icon: tab.icon,
    activeOn: [ERP_ROUTE],
    to: accountScopedRoute(ERP_ROUTE, { tab: tab.name }),
  }));
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
