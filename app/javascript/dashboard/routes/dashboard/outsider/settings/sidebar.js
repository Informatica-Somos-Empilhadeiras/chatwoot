// OUTSIDER: itens do Somos no grupo Configurações do menu lateral (só aparecem para administradores,
// pelas permissões das rotas em ./routes.js)
export const outsiderSettingsItems = (t, accountScopedRoute) => [
  // perfis de acesso (o que cada perfil vê e usa) e o cadastro de técnicos com ramal
  {
    name: 'Settings Outsider Access',
    label: t('OUTSIDER_ACCESS.SIDEBAR'),
    icon: 'i-lucide-shield-check',
    to: accountScopedRoute('outsider_access_settings'),
  },
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
  // Aplicativos: a conta Google de cada pessoa (Gmail, Agenda e Drive) e o app da empresa no Google Cloud
  {
    name: 'Settings Outsider Google',
    label: t('OUTSIDER_APPS.GSET.SIDEBAR'),
    icon: 'i-logos-google-icon',
    to: accountScopedRoute('outsider_google_settings'),
  },
  // aviso novo no navegador e no celular (todos)
  {
    name: 'Settings Outsider Push',
    label: t('OUTSIDER_PUSH.SIDEBAR'),
    icon: 'i-lucide-bell-ring',
    to: accountScopedRoute('outsider_push_settings'),
  },
];
