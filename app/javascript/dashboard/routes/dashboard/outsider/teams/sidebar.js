// OUTSIDER: item Teams no menu lateral, logo abaixo de Conversas (seção Atendimento), com Chats e
// Canais e as não lidas de cada um. Só aparece para quem conectou o próprio Teams.
import { h } from 'vue';
import TeamsLogo from './TeamsLogo.vue';
import { teamsState, teamsVisible, TEAMS_ROUTE } from './teamsStore';

export const teamsSidebarItems = (t, accountScopedRoute) => {
  if (!teamsVisible()) return [];
  return [
    {
      name: 'OutsiderTeams',
      label: t('OUTSIDER_TEAMS_AREA.SIDEBAR'),
      icon: h(TeamsLogo, { size: 18 }),
      navSection: 'atendimento',
      // Chats e Canais não se repetem: o número do item é a soma dos dois
      countMode: 'sum',
      children: [
        {
          name: 'OutsiderTeams-chats',
          label: t('OUTSIDER_TEAMS_AREA.TABS.CHATS'),
          icon: 'i-lucide-message-circle',
          badgeCount: teamsState.unreadChats,
          activeOn: [TEAMS_ROUTE],
          to: accountScopedRoute(TEAMS_ROUTE, { kind: 'chats' }),
        },
        {
          name: 'OutsiderTeams-channels',
          label: t('OUTSIDER_TEAMS_AREA.TABS.CHANNELS'),
          icon: 'i-lucide-hash',
          badgeCount: teamsState.unreadChannels,
          activeOn: [TEAMS_ROUTE],
          to: accountScopedRoute(TEAMS_ROUTE, { kind: 'channels' }),
        },
      ],
    },
  ];
};
