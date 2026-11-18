// OUTSIDER (técnicos): os dados da Tela do Técnico (Meu telefone): os ramais da empresa (quem está livre, em ligação
// ou só pelo aviso no celular) e as ligações recentes da pessoa, com as perdidas que ela ainda não viu (o número
// vermelho na aba Recentes). Busca de novo ao voltar para a tela e quando uma ligação acaba.
import { reactive } from 'vue';
import VoiceAPI from 'dashboard/api/outsider/voice';

const SEEN_KEY = 'outsider_tech_recent_seen';
const STALE = 30000;

export const techState = reactive({
  team: [],
  teamAt: 0,
  recent: [],
  recentAt: 0,
  recentLoaded: false,
  seenAt: 0,
});

try {
  techState.seenAt = Number(localStorage.getItem(SEEN_KEY)) || 0;
} catch {
  techState.seenAt = 0;
}

export const loadTeam = async ({ force = false } = {}) => {
  if (!force && Date.now() - techState.teamAt < STALE) return techState.team;
  try {
    const { data } = await VoiceAPI.team();
    techState.team = data || [];
    techState.teamAt = Date.now();
  } catch {
    // sem resposta: fica a lista de antes
  }
  return techState.team;
};

export const loadRecent = async ({ force = false } = {}) => {
  if (!force && Date.now() - techState.recentAt < STALE) {
    return techState.recent;
  }
  try {
    const { data } = await VoiceAPI.recent();
    techState.recent = data || [];
    techState.recentAt = Date.now();
  } catch {
    // sem resposta: fica a lista de antes
  } finally {
    techState.recentLoaded = true;
  }
  return techState.recent;
};

export const unseenMissed = () =>
  techState.recent.filter(
    call =>
      call.missed && new Date(call.started_at).getTime() > techState.seenAt
  ).length;

export const markRecentSeen = () => {
  techState.seenAt = Date.now();
  try {
    localStorage.setItem(SEEN_KEY, String(techState.seenAt));
  } catch {
    // sem localStorage o número some só nesta tela
  }
};

// colega pelo ramal (nome e foto no teclado, na lista de recentes e na tela da ligação)
export const colleagueOf = extension =>
  techState.team.find(person => person.extension === String(extension || ''));

// livre, em ligação, só pelo aviso (app fechado no celular), ocupado ou sem telefone
export const presenceOf = person => {
  if (!person) return 'offline';
  if (person.in_call) return 'in_call';
  if (person.availability === 'busy') return 'busy';
  if (person.online) return 'online';
  if (person.wakeable) return 'push';
  return 'offline';
};
