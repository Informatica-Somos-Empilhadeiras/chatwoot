// OUTSIDER: texto dos erros das telas dos aplicativos (Outlook, OneDrive, Gmail, Drive, Agenda). Os códigos vêm do
// Apps::BaseController; o que não for daqui (a Agenda da Microsoft ainda usa a API do Teams) cai no texto do Teams.
// Pedido para /outsider/apps/google/...: os textos que falam da empresa vêm do bloco Google (OUTSIDER_APPS.GERRORS).
import { errorText as teamsErrorText } from '../teams/helpers';

const CODES = [
  'not_connected',
  'scope_outdated',
  'reconnect',
  'not_found',
  'forbidden',
  'busy',
  'invalid',
  'graph',
  'no_recipient',
  'no_source',
  'too_big',
];

// só do Google (Configurações > Google e os textos que citam a empresa)
const GOOGLE_CODES = [
  'not_connected',
  'scope_outdated',
  'reconnect',
  'busy',
  'graph',
  'not_configured',
  'already_linked',
  'no_refresh_token',
  'denied',
  'google',
  'state',
];

const isGoogle = error =>
  /\/outsider\/apps\/google\//.test(String(error?.config?.url || ''));

export const errorText = (error, t) => {
  const code = error?.response?.data?.error;
  if (isGoogle(error) && GOOGLE_CODES.includes(code))
    return t(`OUTSIDER_APPS.GERRORS.${code.toUpperCase()}`);
  if (CODES.includes(code))
    return t(`OUTSIDER_APPS.ERRORS.${code.toUpperCase()}`);
  return teamsErrorText(error, t);
};
