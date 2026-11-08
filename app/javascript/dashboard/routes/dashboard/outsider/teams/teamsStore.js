// OUTSIDER: estado da área Teams que aparece fora dela: o item Teams do menu (só para quem conectou o
// próprio Teams) e as não lidas de Chats e Canais. Carrega uma vez por conta e acompanha os avisos ao
// vivo (evento outsider.notice com kind 'teams', mandado só para o dono da área).
import { reactive } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';

export const TEAMS_NOTICE = 'outsider:notice';
export const TEAMS_ROUTE = 'outsider_teams';

export const teamsState = reactive({
  accountId: null,
  connected: false,
  status: null,
  hasThreads: false,
  unreadChats: 0,
  unreadChannels: 0,
  mentions: 0,
  channelView: 'conversa',
});

// o item do menu aparece para quem conectou ou já tem conversas recebidas
export const teamsVisible = () => teamsState.connected || teamsState.hasThreads;

let request = 0;
let listening = false;

export const loadTeamsSummary = async accountId => {
  if (!accountId) return;
  teamsState.accountId = accountId;
  request += 1;
  const mine = request;
  try {
    const { data } = await TeamsGraphAPI.summary();
    if (mine !== request) return;
    Object.assign(teamsState, {
      connected: data.connected,
      status: data.status,
      hasThreads: data.has_threads,
      unreadChats: data.unread_chats,
      unreadChannels: data.unread_channels,
      mentions: data.mentions || 0,
      channelView: data.channel_view || 'conversa',
    });
  } catch {
    // sem o resumo o menu só não mostra o Teams; a área continua abrindo pelo endereço
  }
};

const onNotice = data => {
  if (data?.kind !== 'teams') return;
  if (String(data.account_id) !== String(teamsState.accountId)) return;
  if (data.action === 'message_created' || data.action === 'changed') {
    loadTeamsSummary(teamsState.accountId);
  }
};

export const startTeamsUpdates = accountId => {
  loadTeamsSummary(accountId);
  if (listening) return;
  listening = true;
  emitter.on(TEAMS_NOTICE, onNotice);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, () =>
    loadTeamsSummary(teamsState.accountId)
  );
};
