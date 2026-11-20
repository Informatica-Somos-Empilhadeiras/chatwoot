// OUTSIDER: as telas dos perfis de acesso no painel (mesmas chaves de app/services/outsider/access/catalog.rb) e a
// rota de cada uma. Rota que não está aqui (Configurações, perfil, relatórios...) segue só o papel do Chatwoot.
const ACCOUNT = String.raw`^/app/accounts/\d+/`;
const path = rest => new RegExp(`${ACCOUNT}${rest}`);

// a ordem importa: a primeira que casa vale (Gravações antes do resto da Telefonia)
export const SCREEN_PATHS = [
  ['voice_recordings', path('telefonia/recordings')],
  ['voice_admin', path('telefonia/(ivr|ura|settings)')],
  ['voice_panel', path('telefonia(/|$)')],
  ['phone', path('(meu-telefone|telefone)(/|$)')],
  [
    'conversations',
    path(
      '(dashboard|conversations|inbox|inbox-view|label|team|custom_view|mentions|unattended|participating|search)(/|$)'
    ),
  ],
  ['contacts', path('(contacts|companies)(/|$)')],
  ['whatsapp_status', path('whatsapp-status(/|$)')],
  ['teams', path('teams(/|$)')],
  ['crm', path('crm(/|$)')],
  ['erp', path('erp(/|$)')],
];

export const screenForPath = fullPath => {
  const clean = String(fullPath || '').split(/[?#]/)[0];
  const found = SCREEN_PATHS.find(([, pattern]) => pattern.test(clean));
  return found ? found[0] : null;
};

export const LEVELS = ['none', 'view', 'use', 'manage'];
export const rank = level => Math.max(LEVELS.indexOf(level), 0);

// tela inicial de cada perfil (Resolver#home) -> rota
export const HOME_ROUTES = {
  phone: 'outsider_my_phone',
  conversations: 'home',
  crm: 'outsider_crm',
  teams: 'outsider_teams',
  voice_panel: 'outsider_voice',
  contacts: 'contacts_dashboard_index',
};

export const GROUPS = ['telefonia', 'atendimento', 'vendas'];
