// OUTSIDER: o que muda de uma empresa para outra nas telas dos Aplicativos: nomes, logos, de onde vem a agenda e alguns
// textos (Lixeira x Itens excluídos, estrela x sinalizar...). A Microsoft usa a agenda do Teams (teams_calendar); o
// Google usa a agenda principal da conta Google da pessoa.
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import AppsAPI from 'dashboard/api/outsider/apps';
import { appsState } from './appsStore';

export const PROVIDERS = {
  microsoft: {
    key: 'microsoft',
    company: 'OUTSIDER_APPS.MICROSOFT',
    mail: { logo: 'outlook', name: 'OUTSIDER_APPS.OUTLOOK', feature: 'mail' },
    drive: { logo: 'onedrive', name: 'OUTSIDER_APPS.ONEDRIVE', feature: null },
    calendar: {
      logo: 'mcalendar',
      name: 'OUTSIDER_APPS.CALENDAR',
      source: 'OUTSIDER_APPS.CAL.SOURCE_MICROSOFT',
      feature: 'calendar',
      onlineLabel: 'OUTSIDER_APPS.CAL.ONLINE_TEAMS',
      events: params => TeamsGraphAPI.calendar(params),
      create: data => TeamsGraphAPI.createEvent(data),
      remove: id => TeamsGraphAPI.deleteEvent(id),
      people: () => TeamsGraphAPI.people(),
    },
    // tela de Configurações onde a pessoa conecta a conta
    settingsRoute: 'outsider_teams_settings',
    texts: {},
  },
  google: {
    key: 'google',
    company: 'OUTSIDER_APPS.GOOGLE',
    mail: {
      logo: 'gmail',
      name: 'OUTSIDER_APPS.GMAIL',
      feature: 'mail',
      flagIcon: 'i-lucide-star',
    },
    drive: { logo: 'gdrive', name: 'OUTSIDER_APPS.GDRIVE', feature: 'drive' },
    calendar: {
      logo: 'gcalendar',
      name: 'OUTSIDER_APPS.CALENDAR',
      source: 'OUTSIDER_APPS.G.CAL_SOURCE',
      feature: 'calendar',
      onlineLabel: 'OUTSIDER_APPS.G.CAL_ONLINE',
      invite: 'OUTSIDER_APPS.G.CAL_INVITE',
      events: params => AppsAPI.googleEvents(params),
      create: data => AppsAPI.googleCreateEvent(data),
      remove: id => AppsAPI.googleDeleteEvent(id),
      people: () => AppsAPI.googlePeople(),
    },
    settingsRoute: 'outsider_google_settings',
    texts: {
      'MAIL.DELETE': 'OUTSIDER_APPS.G.MAIL_DELETE',
      'MAIL.DELETED': 'OUTSIDER_APPS.G.MAIL_DELETED',
      'MAIL.FLAG': 'OUTSIDER_APPS.G.MAIL_FLAG',
      'MAIL.UNFLAG': 'OUTSIDER_APPS.G.MAIL_UNFLAG',
      'MAIL.FILTER_FLAGGED': 'OUTSIDER_APPS.G.MAIL_FILTER_FLAGGED',
      'MAIL.OPEN_WEB': 'OUTSIDER_APPS.G.MAIL_OPEN_WEB',
      'MAIL.QUOTED_NOTE': 'OUTSIDER_APPS.G.MAIL_QUOTED_NOTE',
      'DRIVE.CONFIRM_DELETE': 'OUTSIDER_APPS.G.DRIVE_CONFIRM_DELETE',
      'DRIVE.EDIT': 'OUTSIDER_APPS.G.DRIVE_EDIT',
      'GATE.RECONNECT_TEXT': 'OUTSIDER_APPS.G.GATE_RECONNECT_TEXT',
      'GATE.SCOPE_TEXT': 'OUTSIDER_APPS.G.GATE_SCOPE_TEXT',
    },
  },
};

export const providerOf = key => PROVIDERS[key] || PROVIDERS.microsoft;

// chave do texto para a empresa: textKey('google', 'MAIL.DELETE') -> 'OUTSIDER_APPS.G.MAIL_DELETE'
export const textKey = (key, path) =>
  providerOf(key).texts[path] || `OUTSIDER_APPS.${path}`;

// estado da conta para a tela: 'loading' | 'disconnected' | 'reconnect' | 'scope' | 'ready'
export const gateOf = (key, feature) => {
  const state = appsState[key];
  if (!state || !state.loaded) return 'loading';
  if (!state.connected) return 'disconnected';
  if (state.status === 'reconnect') return 'reconnect';
  if (feature && !state[feature]) return 'scope';
  return 'ready';
};
