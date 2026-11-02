// OUTSIDER: itens do Somos no grupo Configurações do menu lateral (só aparecem para administradores,
// pelas permissões das rotas em ./routes.js)
export const outsiderSettingsItems = (t, accountScopedRoute) => [
  {
    name: 'Settings Outsider Appearance',
    label: t('OUTSIDER_TOOLS.SETTINGS.APPEARANCE'),
    icon: 'i-lucide-palette',
    to: accountScopedRoute('outsider_branding_settings'),
  },
  {
    name: 'Settings Outsider Bots',
    label: t('OUTSIDER_TOOLS.SETTINGS.BOTS'),
    icon: 'i-lucide-workflow',
    activeOn: ['outsider_bot_flows', 'outsider_bot_flow_editor'],
    to: accountScopedRoute('outsider_bot_flows'),
  },
  // Entrega 26
  {
    name: 'Settings Outsider Teams',
    label: t('OUTSIDER_TEAMS.SIDEBAR'),
    icon: 'i-lucide-messages-square',
    to: accountScopedRoute('outsider_teams_settings'),
  },
];
