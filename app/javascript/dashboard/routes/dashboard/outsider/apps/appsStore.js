// OUTSIDER: estado dos Aplicativos que aparece fora das telas deles: quem está conectado (Microsoft e Google) e as não
// lidas do Outlook e do Gmail para o número do menu. Carrega uma vez por conta e acompanha os avisos ao vivo (evento
// outsider.notice com kind 'apps', mandado só para a própria pessoa). Mudou o login do Teams (kind 'teams', action
// 'changed') ou do Google (kind 'apps' sem número): recarrega.
import { reactive } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import AppsAPI from 'dashboard/api/outsider/apps';

export const APPS_NOTICE = 'outsider:notice';
export const MAIL_ROUTE = 'outsider_apps_mail';
export const DRIVE_ROUTE = 'outsider_apps_drive';
export const CALENDAR_ROUTE = 'outsider_apps_calendar';

const emptyProvider = () => ({
  loaded: false,
  // a empresa ligou o app (Configurações > Microsoft Teams / Configurações > Google): o bloco aparece para todos
  configured: false,
  connected: false,
  status: null,
  email: '',
  mail: false,
  calendar: false,
  drive: false,
  unreadMail: 0,
});

export const appsState = reactive({
  accountId: null,
  microsoft: emptyProvider(),
  google: emptyProvider(),
});

const PROVIDER_KEYS = ['microsoft', 'google'];

let request = 0;
let listening = false;

export const loadAppsSummary = async accountId => {
  if (!accountId) return;
  appsState.accountId = accountId;
  request += 1;
  const mine = request;
  try {
    const { data } = await AppsAPI.summary();
    if (mine !== request) return;
    PROVIDER_KEYS.forEach(key => {
      const info = data[key] || {};
      Object.assign(appsState[key], {
        loaded: true,
        configured: !!info.configured,
        connected: !!info.connected,
        status: info.status || null,
        email: info.email || '',
        mail: !!info.mail,
        calendar: !!info.calendar,
        // OneDrive vem junto com o login do Teams desde a primeira versão
        drive: key === 'microsoft' ? !!info.connected : !!info.drive,
        unreadMail: info.unread_mail || 0,
      });
    });
  } catch {
    PROVIDER_KEYS.forEach(key => {
      appsState[key].loaded = true;
    });
  }
};

// a tela do e-mail avisa quando a pessoa leu/marcou algo, para o número do menu acompanhar
export const setUnreadMail = (provider, count) => {
  if (appsState[provider] && Number.isFinite(count))
    appsState[provider].unreadMail = Math.max(0, count);
};

const onNotice = data => {
  if (String(data?.account_id) !== String(appsState.accountId)) return;
  if (data.kind === 'apps' && data.app === 'mail' && appsState[data.provider]) {
    if (Number.isFinite(data.unread)) setUnreadMail(data.provider, data.unread);
    else loadAppsSummary(appsState.accountId);
  }
  if (data.kind === 'teams' && data.action === 'changed')
    loadAppsSummary(appsState.accountId);
};

export const startAppsUpdates = accountId => {
  loadAppsSummary(accountId);
  if (listening) return;
  listening = true;
  emitter.on(APPS_NOTICE, onNotice);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, () =>
    loadAppsSummary(appsState.accountId)
  );
};
