// OUTSIDER: menu "ERP" no menu lateral (secao Atendimento) com uma aba por modulo, em quatro grupos (os mesmos das abas
// da secao, ErpIndex): Orcamentos e OS (orcamentos, OS, produtos), Fiscal e financeiro (pedidos, notas fiscais),
// Relatorios e desempenho (os relatorios de reports/reportsCatalog.js e os Modelos de relatorio) e Configuracoes. Cada
// aba segue o que esta ligado nas Configuracoes e a linha dela no perfil de acesso (erp_quotes, erp_orders, erp_sales,
// erp_invoices, erp_products, abaixo da tela "erp"); com a integracao desligada so o admin ve. Grupo sem aba some.
// No menu do computador os grupos usam o titulo em destaque (groupStyle 'strong', NavGroups.vue): maior que as abas,
// e as abas recuadas embaixo, na linha da arvore.
import { allows } from '../access/accessStore';
import { erpState, ERP_ROUTE } from './erpStore';
import { reportTabs } from '../reports/reportsCatalog';

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
  // modelos de relatório da OS e do orçamento (estúdio), só para o administrador
  {
    name: 'modelos',
    label: 'OUTSIDER_ERP.TABS.MODELOS',
    icon: 'i-lucide-printer',
  },
  {
    name: 'settings',
    label: 'OUTSIDER_ERP.TABS.SETTINGS',
    icon: 'i-lucide-settings-2',
  },
];

// os grupos, na ordem do menu; '@reports' = os relatórios que a pessoa abre
export const ERP_GROUPS = [
  {
    key: 'vendas',
    label: 'OUTSIDER_ERP.GROUPS.SALES',
    icon: 'i-lucide-clipboard-list',
    tabs: ['orcamentos', 'os', 'produtos'],
  },
  {
    key: 'fiscal',
    label: 'OUTSIDER_ERP.GROUPS.FISCAL',
    icon: 'i-lucide-landmark',
    tabs: ['pedidos', 'notas'],
  },
  {
    key: 'relatorios',
    label: 'OUTSIDER_ERP.GROUPS.REPORTS',
    icon: 'i-lucide-chart-column',
    tabs: ['@reports', 'modelos'],
  },
  {
    key: 'config',
    label: 'OUTSIDER_ERP.GROUPS.SETTINGS',
    icon: 'i-lucide-settings-2',
    tabs: ['settings'],
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
    modelos: erpState.enabled && erpState.administrator,
    settings: erpState.administrator,
  };
  return ERP_TABS.filter(tab => open[tab.name]);
};

// as abas abertas, por grupo: [{ key, label, icon, items: [aba] }], só os grupos com alguma aba
export const erpGroups = () => {
  const open = erpTabs();
  const reports = erpState.loaded ? reportTabs() : [];
  return ERP_GROUPS.map(group => ({
    ...group,
    items: group.tabs.flatMap(name =>
      name === '@reports' ? reports : open.filter(tab => tab.name === name)
    ),
  })).filter(group => group.items.length);
};

export const erpSidebarItems = (t, accountScopedRoute) => {
  const leaf = tab => ({
    name: `OutsiderErp-${tab.name}`,
    label: t(tab.label),
    icon: tab.icon,
    activeOn: [ERP_ROUTE],
    to: accountScopedRoute(ERP_ROUTE, { tab: tab.name }),
  });
  const children = erpGroups().map(group => ({
    name: `OutsiderErp-group-${group.key}`,
    label: t(group.label),
    icon: group.icon,
    groupStyle: 'strong',
    children: group.items.map(leaf),
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
