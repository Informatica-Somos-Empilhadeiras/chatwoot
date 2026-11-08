// OUTSIDER: em que seção do menu lateral cada módulo aparece, e em que ordem.
//
// - Os nomes são os "name" dos itens do menuItems do Sidebar.vue (Chatwoot e módulos outsider).
// - Um módulo novo pode escolher a própria seção sem mexer aqui: basta o item do menu ter
//   navSection: 'atendimento' | 'vendas' | 'gestao'.
// - Item que não está em nenhuma lista (ex.: um módulo que o Chatwoot criar numa atualização)
//   entra na seção "Mais", então nada some do menu.
export const NAV_SECTIONS = [
  {
    key: 'atendimento',
    label: 'OUTSIDER_NAV.SECTIONS.SERVICE',
    items: ['Conversation', 'OutsiderTeams', 'Inbox', 'WhatsappStatus'],
  },
  {
    key: 'vendas',
    label: 'OUTSIDER_NAV.SECTIONS.SALES',
    items: ['OutsiderCrm', 'OutsiderVoice', 'Contacts', 'Companies'],
  },
  {
    key: 'gestao',
    label: 'OUTSIDER_NAV.SECTIONS.MANAGE',
    items: ['Reports', 'Campaigns', 'Captain', 'Portals', 'Settings'],
  },
];

export const NAV_FALLBACK_SECTION = {
  key: 'mais',
  label: 'OUTSIDER_NAV.SECTIONS.MORE',
};

// módulos -> [{ key, label, modules }] (seções vazias ficam de fora)
export const groupBySection = modules => {
  const sections = NAV_SECTIONS.map(section => ({ ...section, modules: [] }));
  const fallback = { ...NAV_FALLBACK_SECTION, modules: [] };
  const byKey = Object.fromEntries(sections.map(s => [s.key, s]));

  modules.forEach(module => {
    const own = module.navSection && byKey[module.navSection];
    const listed = sections.find(s => s.items.includes(module.name));
    (own || listed || fallback).modules.push(module);
  });

  sections.forEach(section => {
    section.modules.sort((a, b) => {
      const ia = section.items.indexOf(a.name);
      const ib = section.items.indexOf(b.name);
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
    });
  });

  return [...sections, fallback].filter(s => s.modules.length);
};
