// OUTSIDER: blocos dos Aplicativos no menu lateral (seção Aplicativos): um por empresa, com o logo dela, e dentro os
// aplicativos com o próprio ícone e o número de não lidas. Microsoft: Teams, Outlook, OneDrive e Agenda (a Agenda saiu
// de dentro do Teams). O menu do computador mostra o bloco como uma grade de ícones (layout 'apps'); recolhido, no
// celular e em qualquer outro lugar ele é um módulo comum, com os aplicativos como opções.
// O bloco aparece para quem conectou a conta Microsoft (ou já tem conversas do Teams) e para todos quando a empresa
// já ligou o app da Microsoft: quem ainda não conectou vê na tela o botão para conectar.
import { h } from 'vue';
import AppLogo from './AppLogo.vue';
import {
  appsState,
  MAIL_ROUTE,
  DRIVE_ROUTE,
  CALENDAR_ROUTE,
} from './appsStore';
import { teamsState, teamsVisible, TEAMS_ROUTE } from '../teams/teamsStore';

const logo = name => h(AppLogo, { name, size: 18 });

export const microsoftVisible = () =>
  teamsVisible() ||
  appsState.microsoft.connected ||
  appsState.microsoft.configured;

const microsoftModule = (t, accountScopedRoute) => {
  const provider = { provider: 'microsoft' };
  const status = appsState.microsoft.connected
    ? appsState.microsoft.status
    : teamsState.status;
  return {
    name: 'OutsiderMicrosoft',
    label: t('OUTSIDER_APPS.MICROSOFT'),
    icon: logo('microsoft'),
    navSection: 'aplicativos',
    layout: 'apps',
    appStatus: status || 'disconnected',
    // cada aplicativo conta o que é dele (não se repetem): o número do bloco é a soma
    countMode: 'sum',
    children: [
      {
        name: 'OutsiderMicrosoft-teams',
        label: t('OUTSIDER_APPS.TEAMS'),
        icon: logo('teams'),
        badgeCount: teamsState.unreadChats + teamsState.unreadChannels,
        activeOn: [TEAMS_ROUTE],
        to: accountScopedRoute(TEAMS_ROUTE, { kind: 'chats' }),
      },
      {
        name: 'OutsiderMicrosoft-outlook',
        label: t('OUTSIDER_APPS.OUTLOOK'),
        icon: logo('outlook'),
        badgeCount: appsState.microsoft.unreadMail,
        activeOn: [MAIL_ROUTE],
        to: accountScopedRoute(MAIL_ROUTE, { ...provider, mailApp: 'outlook' }),
      },
      {
        name: 'OutsiderMicrosoft-onedrive',
        label: t('OUTSIDER_APPS.ONEDRIVE'),
        icon: logo('onedrive'),
        activeOn: [DRIVE_ROUTE],
        to: accountScopedRoute(DRIVE_ROUTE, {
          ...provider,
          driveApp: 'onedrive',
        }),
      },
      {
        name: 'OutsiderMicrosoft-calendar',
        label: t('OUTSIDER_APPS.CALENDAR'),
        icon: logo('mcalendar'),
        activeOn: [CALENDAR_ROUTE],
        to: accountScopedRoute(CALENDAR_ROUTE, provider),
      },
    ],
  };
};

export const appsSidebarItems = (t, accountScopedRoute) => {
  const items = [];
  if (microsoftVisible()) items.push(microsoftModule(t, accountScopedRoute));
  return items;
};
