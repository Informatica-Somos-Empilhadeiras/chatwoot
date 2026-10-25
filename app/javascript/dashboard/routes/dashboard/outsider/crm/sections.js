// OUTSIDER: seções do CRM (Negócios, Tarefas, Propostas, Catálogo, Metas, Ligações, Relatórios, Configurações). Aparecem como
// subitens do CRM no menu lateral do Chatwoot e decidem o que a tela do CRM mostra (rota crm/:tab).
export const CRM_ROUTE = 'outsider_crm';

const SECTIONS = [
  { key: 'opportunities', icon: 'i-lucide-kanban' },
  { key: 'tasks', icon: 'i-lucide-list-checks' },
  { key: 'proposals', icon: 'i-lucide-file-text' },
  { key: 'catalog', icon: 'i-lucide-package' },
  { key: 'goals', icon: 'i-lucide-target' },
  // só com a telefonia ligada (Configurações > Telefonia)
  { key: 'calls', icon: 'i-lucide-phone' },
  { key: 'reports', icon: 'i-lucide-chart-column' },
  { key: 'settings', icon: 'i-lucide-settings-2' },
];

// Configurações: administrador e gestor de unidade (pipelines e membros das suas unidades)
export const canConfigure = access =>
  access.administrator || access.units.some(unit => unit.role === 'manager');

export const crmSections = access =>
  SECTIONS.filter(
    section =>
      (section.key !== 'settings' || canConfigure(access)) &&
      (section.key !== 'calls' || access.voice)
  ).map(section => ({
    ...section,
    label: `OUTSIDER_CRM.TABS.${section.key.toUpperCase()}`,
  }));
