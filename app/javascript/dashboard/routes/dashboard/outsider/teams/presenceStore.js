// OUTSIDER: quem está online no Teams (bolinha verde, amarela, vermelha ou cinza, como no Teams). As telas pedem
// a presença das pessoas que estão aparecendo (watch) e o estado chega aqui a cada 45 s, numa pergunta só para a
// Microsoft. Só funciona para quem entrou com as permissões novas (versão 2).
import { reactive } from 'vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';

const EVERY = 45 * 1000;
const MAX_IDS = 650; // limite da Microsoft por pergunta

export const presenceState = reactive({
  // id da Microsoft -> { availability, activity }
  byId: {},
  enabled: true,
});

const watched = new Map(); // id -> quantas telas pedem
let timer = null;
let inFlight = false;

const fetchNow = async () => {
  const ids = [...watched.keys()].slice(0, MAX_IDS);
  if (!ids.length || inFlight || !presenceState.enabled) return;
  inFlight = true;
  try {
    const { data } = await TeamsGraphAPI.presence(ids);
    if (data.unavailable) {
      presenceState.enabled = false;
      return;
    }
    const next = { ...presenceState.byId };
    (data.payload || []).forEach(item => {
      next[item.id] = {
        availability: item.availability,
        activity: item.activity,
      };
    });
    presenceState.byId = next;
  } catch {
    // sem presença a tela só fica sem a bolinha
  } finally {
    inFlight = false;
  }
};

const schedule = () => {
  if (timer) return;
  timer = setInterval(fetchNow, EVERY);
};

// pede a presença dessas pessoas enquanto a tela estiver aberta; devolve a função para parar de pedir
export const watchPresence = ids => {
  const list = ids.filter(Boolean);
  let fresh = false;
  list.forEach(id => {
    if (!watched.has(id)) fresh = true;
    watched.set(id, (watched.get(id) || 0) + 1);
  });
  if (fresh) fetchNow();
  schedule();
  return () => {
    list.forEach(id => {
      const count = (watched.get(id) || 1) - 1;
      if (count <= 0) watched.delete(id);
      else watched.set(id, count);
    });
    if (!watched.size && timer) {
      clearInterval(timer);
      timer = null;
    }
  };
};

export const presenceOf = id => (id ? presenceState.byId[id] : null) || null;

// cor e texto da bolinha, como no Teams
export const PRESENCE = {
  Available: { color: '#6bb700', key: 'AVAILABLE' },
  AvailableIdle: { color: '#6bb700', key: 'AVAILABLE' },
  Busy: { color: '#c4314b', key: 'BUSY' },
  BusyIdle: { color: '#c4314b', key: 'BUSY' },
  DoNotDisturb: { color: '#c4314b', key: 'DND' },
  Away: { color: '#ffaa44', key: 'AWAY' },
  BeRightBack: { color: '#ffaa44', key: 'BRB' },
  Offline: { color: '#8a8886', key: 'OFFLINE' },
  PresenceUnknown: { color: '#8a8886', key: 'UNKNOWN' },
};

export const presenceStyle = id => {
  const info = presenceOf(id);
  if (!info) return null;
  return PRESENCE[info.availability] || PRESENCE.PresenceUnknown;
};
