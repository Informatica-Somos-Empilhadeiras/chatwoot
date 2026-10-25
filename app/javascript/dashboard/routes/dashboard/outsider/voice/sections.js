// OUTSIDER: seções da Telefonia (Entrega 23). Painel e Ligações com a telefonia ligada; Configurações só
// para administradores (é lá que ela é ligada). Usa o acesso do CRM: a Telefonia guarda as ligações nos
// negócios e tarefas dele.
export const VOICE_ROUTE = 'outsider_voice';

const SECTIONS = [
  { key: 'dashboard', icon: 'i-lucide-layout-dashboard', voice: true },
  { key: 'calls', icon: 'i-lucide-phone-call', voice: true },
  { key: 'settings', icon: 'i-lucide-settings-2', admin: true },
];

export const voiceSections = access =>
  SECTIONS.filter(
    section =>
      access.enabled &&
      (!section.voice || access.voice) &&
      (!section.admin || access.administrator)
  ).map(section => ({
    ...section,
    label: `OUTSIDER_VOICE.SECTION.TABS.${section.key.toUpperCase()}`,
  }));
