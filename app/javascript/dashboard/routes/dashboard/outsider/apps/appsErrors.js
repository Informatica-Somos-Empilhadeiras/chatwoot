// OUTSIDER: texto dos erros das telas dos aplicativos (Outlook, OneDrive, Agenda). Os códigos vêm do
// Apps::BaseController; o que não for daqui (a Agenda ainda usa a API do Teams) cai no texto do Teams.
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

export const errorText = (error, t) => {
  const code = error?.response?.data?.error;
  if (CODES.includes(code))
    return t(`OUTSIDER_APPS.ERRORS.${code.toUpperCase()}`);
  return teamsErrorText(error, t);
};
