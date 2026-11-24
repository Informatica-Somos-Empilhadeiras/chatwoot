// OUTSIDER: o que muda de uma empresa para outra nas telas dos Aplicativos: nomes, logos e de onde vem a agenda.
// A Microsoft usa a agenda do Teams (teams_calendar); o Google entra aqui na próxima entrega.
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
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
  },
};

export const providerOf = key => PROVIDERS[key] || PROVIDERS.microsoft;

// estado da conta para a tela: 'loading' | 'disconnected' | 'reconnect' | 'scope' | 'ready'
export const gateOf = (key, feature) => {
  const state = appsState[key];
  if (!state || !state.loaded) return 'loading';
  if (!state.connected) return 'disconnected';
  if (state.status === 'reconnect') return 'reconnect';
  if (feature && !state[feature]) return 'scope';
  return 'ready';
};
