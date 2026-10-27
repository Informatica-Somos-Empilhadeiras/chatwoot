// OUTSIDER: o telefone do navegador (Entrega 22). Entra na central (Asterisk) com o ramal da pessoa, pela
// conexão WebSocket da central (JsSIP), e faz e recebe ligações com o microfone e o fone do computador.
//
// Só uma aba (ou a janela própria do telefone) fica com a linha (Web Locks). Entrega 24: as outras abas viram
// controle remoto dela (BroadcastChannel): mostram a mesma ligação e os botões funcionam, mandando o pedido
// para a aba que está com a linha. Ao fechar a aba que estava com ela, a próxima assume sozinha.
//
// Conferência (Entrega 24): a pessoa liga para mais gente sem desligar a primeira ligação. Cada pessoa é uma
// ligação própria na central; a mistura do áudio é feita aqui, no navegador (Web Audio): cada um ouve você e
// todos os outros. Gravar junta o seu microfone e o som de todos num arquivo, enviado no fim da ligação.
//
// O estado fica em `phone` (reativo): as telas leem; para agir, chamam as funções exportadas.
import { reactive, watch } from 'vue';
import VoiceAPI from 'dashboard/api/outsider/voice';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { startTone, stopTone } from './ringtone';

const ICE_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }];
// a ligação sai com os endereços que o navegador achou até aqui (o endereço público vem do STUN)
const ICE_WAIT = 1500;
// "Ocupado", "Não atendeu"... ficam na tela por um tempo depois que a ligação acaba
const ENDED_VISIBLE = 4000;
const GUEST_ENDED_VISIBLE = 3000;
// ramal recém-ligado nas Configurações: a central só o conhece depois de buscar a configuração (até 30 s)
export const CENTRAL_SYNC_WAIT = 35000;
// na conferência: você e mais até 5 pessoas (a primeira ligação e 4 incluídas)
export const MAX_GUESTS = 4;
const MEDIA = { audio: true, video: false };
const RECORDING_BITRATE = 32000;
const RECORDING_TYPES = [
  'audio/webm;codecs=opus',
  'audio/ogg;codecs=opus',
  'audio/webm',
];
const POPOUT_NAME = 'outsider-phone';
const POPOUT_FEATURES = 'popup,width=400,height=760';
// a janela própria espera um pouco a resposta das abas antes de tomar a linha (para não derrubar ligação)
const POPOUT_HANDSHAKE = 400;

// status: off (sem telefone: telefonia ou ramal desligados), connecting, ready, offline (sem conexão com a
// central), failed (a central recusou o ramal) ou other_tab (outra aba está com a linha e não respondeu)
// holder: esta aba está com a linha; popout: a linha está na janela própria do telefone
// call.others: as pessoas incluídas na conferência; notice: aviso para as telas (gravação salva...)
export const phone = reactive({
  status: 'off',
  extension: '',
  echoExtension: '',
  recordingAllowed: false,
  call: null,
  holder: false,
  popout: false,
  notice: null,
});

// painel do telefone aberto (fixo na tela) ou minimizado e onde ele está (arrastado); guardado no navegador
const PANEL_KEY = 'outsider_phone_panel';
const POSITION_KEY = 'outsider_phone_position';
const readStorage = (key, fallback) => {
  try {
    return localStorage.getItem(key) ?? fallback;
  } catch {
    return fallback;
  }
};
const writeStorage = (key, value) => {
  try {
    localStorage.setItem(key, value);
  } catch {
    // sem localStorage o painel só não lembra como estava
  }
};
const readPosition = () => {
  try {
    const position = JSON.parse(readStorage(POSITION_KEY, 'null'));
    return position && Number.isFinite(position.right) ? position : null;
  } catch {
    return null;
  }
};
export const panel = reactive({
  open: readStorage(PANEL_KEY, 'closed') === 'open',
  position: readPosition(),
});

export const setPanelOpen = open => {
  panel.open = open;
  writeStorage(PANEL_KEY, open ? 'open' : 'closed');
};

// distância do canto inferior direito da tela; null volta ao canto
export const setPanelPosition = position => {
  panel.position = position;
  writeStorage(POSITION_KEY, JSON.stringify(position));
};

let JsSIP = null;
let config = null;
let accountKey = null;
let ua = null;
let releaseLock = null;
let waiting = null;
let generation = 0;
let endedTimer = null;
let channel = null;
let asPopout = false;
let popoutRef = null;
let nextId = 1;
// o próximo newRTCSession de saída (o ua.call dispara na hora): ligação nova ou pessoa incluída
let outgoing = null;
// id -> { session, audio, micTrack, remote, dest }: a ligação principal (phone.call) e as incluídas
const legs = new Map();
let mixer = null;
let recorder = null;

const digitsOf = value => String(value || '').replace(/\D/g, '');

const notify = code => {
  phone.notice = { code, at: Date.now() };
};

const legState = id => {
  if (!phone.call) return null;
  if (phone.call.id === id) return phone.call;
  return phone.call.others.find(other => other.id === id) || null;
};

const mainLeg = () => phone.call && legs.get(phone.call.id);

const audioSender = session =>
  session?.connection
    ?.getSenders()
    .find(sender => sender.track?.kind === 'audio');

const endReason = ({ originator, cause, message }) => {
  const { causes } = JsSIP.C;
  if (originator === 'local' || cause === causes.BYE) return 'DONE';
  if (cause === causes.BUSY) return 'BUSY';
  if (cause === causes.USER_DENIED_MEDIA_ACCESS) return 'MICROPHONE';
  if (cause === causes.CANCELED) {
    // outro vendedor atendeu (a central cancela com "cause=200") ou o cliente desligou antes
    const reason = message?.getHeader?.('Reason') || '';
    return reason.includes('cause=200') ? 'ELSEWHERE' : 'CANCELED';
  }
  if ([causes.NO_ANSWER, causes.EXPIRES].includes(cause)) return 'NO_ANSWER';
  if (
    [
      causes.REJECTED,
      causes.UNAVAILABLE,
      causes.NOT_FOUND,
      causes.ADDRESS_INCOMPLETE,
    ].includes(cause)
  ) {
    return 'UNAVAILABLE';
  }
  return 'FAILED';
};

// --- mistura do áudio (conferência e gravação) ---

const activeLegs = () =>
  phone.call
    ? [phone.call, ...phone.call.others]
        .filter(state => state.state === 'active')
        .map(state => legs.get(state.id))
        .filter(Boolean)
    : [];

const closeMixer = () => {
  mixer?.context.close().catch(() => {});
  mixer = null;
};

const ensureMixer = () => {
  if (!mixer) {
    const context = new AudioContext();
    mixer = {
      context,
      record: context.createMediaStreamDestination(),
      nodes: [],
    };
  }
  mixer.context.resume();
  return mixer;
};

const useOwnMicrophone = active =>
  active.forEach(leg => {
    const sender = audioSender(leg.session);
    if (sender && leg.micTrack && sender.track !== leg.micTrack) {
      sender.replaceTrack(leg.micTrack);
    }
  });

// quem estava na ligação (a principal e a conferência), com a hora em que cada um começou aqui
const callParties = () =>
  phone.call
    ? [phone.call, ...phone.call.others].map(({ number, startedAt }) => ({
        number,
        started_at: startedAt,
      }))
    : [];

const isExternal = number => (number || '').length > 4;

// refeita a cada pessoa que entra ou sai: cada ligação recebe o seu microfone e o som das outras
const remix = () => {
  const active = activeLegs();
  const conference = active.length > 1;
  if (!conference && !recorder) {
    useOwnMicrophone(active);
    return;
  }
  const { context, record } = ensureMixer();
  mixer.nodes.forEach(node => node.disconnect());
  const micTrack = active.find(leg => leg.micTrack)?.micTrack;
  const mic = micTrack
    ? context.createMediaStreamSource(new MediaStream([micTrack]))
    : null;
  const remotes = active.map(leg =>
    leg.remote?.getAudioTracks().length
      ? context.createMediaStreamSource(leg.remote)
      : null
  );
  mixer.nodes = [mic, ...remotes].filter(Boolean);
  if (recorder) {
    mixer.nodes.forEach(node => node.connect(record));
    callParties().forEach(party => recorder.parties.set(party.number, party));
  }
  if (!conference) {
    useOwnMicrophone(active);
    return;
  }
  active.forEach((leg, index) => {
    leg.dest = leg.dest || context.createMediaStreamDestination();
    mic?.connect(leg.dest);
    remotes.forEach((remote, other) => {
      if (other !== index) remote?.connect(leg.dest);
    });
    const sender = audioSender(leg.session);
    const [track] = leg.dest.stream.getAudioTracks();
    if (sender && sender.track !== track) sender.replaceTrack(track);
  });
};

// --- gravação ---

// grava só com cliente na ligação: a gravação fica na ligação dele, em Telefonia > Ligações
export const canRecord = () =>
  !!phone.call &&
  [phone.call, ...phone.call.others].some(
    party => party.state === 'active' && isExternal(party.number)
  );

const uploadRecording = async (blob, parties) => {
  if (!blob.size) return;
  notify('RECORDING_SAVING');
  try {
    await VoiceAPI.uploadRecording(blob, parties);
    notify('RECORDING_SAVED');
  } catch {
    notify('RECORDING_FAILED');
  }
};

const stopRecording = () => {
  if (!recorder) return false;
  const { media, chunks, parties } = recorder;
  callParties().forEach(party => parties.set(party.number, party));
  recorder = null;
  // cliente primeiro: a gravação vai para a ligação dele
  const list = [...parties.values()].sort(
    (a, b) => isExternal(b.number) - isExternal(a.number)
  );
  media.onstop = () => {
    uploadRecording(new Blob(chunks, { type: media.mimeType }), list);
    if (!phone.call || phone.call.state === 'ended') closeMixer();
  };
  media.stop();
  return true;
};

// --- as ligações (pernas) ---

// colegas com ramal (nome de quem está no ramal), buscados no máximo a cada minuto
let team = { at: 0, list: [] };
const teamName = async extension => {
  if (Date.now() - team.at > 60000) {
    const { data } = await VoiceAPI.team();
    team = { at: Date.now(), list: data };
  }
  return team.list.find(person => person.extension === extension)?.name;
};

// quem é: o contato e o negócio do número, ou o nome do colega no ramal
const lookup = async (id, number) => {
  try {
    if (number.length <= 4) {
      const name = await teamName(number);
      const state = legState(id);
      if (name && state?.number === number && !state.name) state.name = name;
      return;
    }
    if (number.length < 8) return;
    const { data } = await VoiceAPI.lookup(number);
    const state = legState(id);
    if (state?.number === number) state.lookup = data;
  } catch {
    // sem nome a ligação continua normal
  }
};

const newCall = info => ({
  ...info,
  muted: false,
  held: false,
  transferTo: '',
  answeredAt: null,
  endReason: '',
  lookup: null,
  // hora em que começou aqui: a gravação acha a ligação certa no Chatwoot por ela e pelo número
  startedAt: new Date().toISOString(),
  recording: '',
  others: [],
});

const finishCall = reason => {
  stopTone();
  const sessions = [...legs.values()].map(leg => leg.session);
  legs.forEach(leg => {
    leg.audio.srcObject = null;
  });
  legs.clear();
  sessions.forEach(session => {
    if (!session.isEnded()) session.terminate();
  });
  if (!stopRecording()) closeMixer();
  const call = phone.call;
  call.others.forEach(other => {
    if (other.state !== 'ended') {
      other.state = 'ended';
      other.endReason = 'DONE';
    }
  });
  call.state = 'ended';
  call.recording = '';
  // ramal "indisponível": a pessoa não está com o telefone aberto (ou o ramal está desligado)
  if (call.transferTo) call.endReason = 'TRANSFERRED';
  else if (reason === 'UNAVAILABLE' && call.number.length <= 4) {
    call.endReason = 'EXTENSION_OFFLINE';
  } else call.endReason = reason;
  clearTimeout(endedTimer);
  endedTimer = setTimeout(() => {
    if (phone.call?.state === 'ended') phone.call = null;
  }, ENDED_VISIBLE);
};

// a primeira ligação acabou e ainda tem gente na conferência: a próxima pessoa vira a principal
const promote = guest => {
  const { others, muted, recording, startedAt } = phone.call;
  phone.call = {
    ...newCall({
      id: guest.id,
      direction: 'outbound',
      number: guest.number,
      name: guest.name,
      state: guest.state,
    }),
    answeredAt: guest.answeredAt,
    lookup: guest.lookup,
    muted,
    recording,
    startedAt: guest.startedAt || startedAt,
    others: others.filter(other => other.id !== guest.id),
  };
};

const endLeg = (id, reason) => {
  const leg = legs.get(id);
  if (!leg || !phone.call) return;
  legs.delete(id);
  leg.audio.srcObject = null;
  if (id !== phone.call.id) {
    const guest = legState(id);
    if (guest?.state === 'dialing') stopTone();
    if (guest) {
      guest.state = 'ended';
      guest.endReason = reason;
      setTimeout(() => {
        if (phone.call) {
          phone.call.others = phone.call.others.filter(
            other => other.id !== id
          );
        }
      }, GUEST_ENDED_VISIBLE);
    }
    remix();
    return;
  }
  const next = phone.call.transferTo
    ? null
    : phone.call.others.find(
        other => other.state !== 'ended' && legs.has(other.id)
      );
  if (next) {
    promote(next);
    remix();
    return;
  }
  finishCall(reason);
};

const listenRemote = (leg, connection) => {
  connection.addEventListener('track', event => {
    [leg.remote] = event.streams;
    leg.audio.srcObject = leg.remote;
    remix();
  });
};

const setupLeg = (id, current) => {
  const audio = new Audio();
  audio.autoplay = true;
  const leg = { session: current, audio, micTrack: null, remote: null };
  legs.set(id, leg);
  let iceTimer = null;
  current.on('icecandidate', ({ candidate, ready }) => {
    if (candidate.type === 'srflx') ready();
    else if (!iceTimer) iceTimer = setTimeout(ready, ICE_WAIT);
  });
  if (current.connection) listenRemote(leg, current.connection);
  else {
    current.on('peerconnection', ({ peerconnection }) =>
      listenRemote(leg, peerconnection)
    );
  }
  // quem liga ouve "chamando" enquanto o outro lado só avisa que está tocando (180); com o som da operadora
  // (183 com áudio), toca o som dela
  current.on('progress', ({ originator, response }) => {
    if (originator !== 'remote' || legState(id)?.state !== 'dialing') return;
    if (response.body) stopTone();
    else if (response.status_code === 180) startTone('ringback');
  });
  current.on('accepted', () => {
    stopTone();
    const state = legState(id);
    if (!state) return;
    state.state = 'active';
    state.answeredAt = Date.now();
    leg.micTrack = audioSender(current)?.track || null;
    if (leg.micTrack && phone.call.muted) leg.micTrack.enabled = false;
    remix();
  });
  current.on('ended', event => endLeg(id, endReason(event)));
  current.on('failed', event => endLeg(id, endReason(event)));
};

const onSession = ({ session: current, originator, request }) => {
  if (originator === 'local') {
    const target = outgoing;
    outgoing = null;
    if (target.guest) {
      phone.call.others.push({
        id: target.id,
        number: target.number,
        name: '',
        state: 'dialing',
        answeredAt: null,
        startedAt: new Date().toISOString(),
        endReason: '',
        lookup: null,
      });
    } else {
      clearTimeout(endedTimer);
      phone.call = newCall({
        id: target.id,
        direction: 'outbound',
        number: target.number,
        name: '',
        state: 'dialing',
      });
    }
    setupLeg(target.id, current);
    lookup(target.id, target.number);
    return;
  }
  // já em ligação: a central toca para os outros
  if (phone.call && phone.call.state !== 'ended') {
    current.terminate({ status_code: 486 });
    return;
  }
  const id = nextId;
  nextId += 1;
  clearTimeout(endedTimer);
  const number = request.from.uri.user || '';
  phone.call = newCall({
    id,
    direction: 'inbound',
    number,
    name: request.from.display_name || '',
    state: 'ringing',
  });
  setupLeg(id, current);
  lookup(id, number);
  startTone('incoming');
};

// --- linha: conexão com a central ---

const disconnect = () => {
  generation += 1;
  stopTone();
  const sessions = [...legs.values()].map(leg => leg.session);
  legs.clear();
  sessions.forEach(session => {
    if (!session.isEnded()) session.terminate();
  });
  stopRecording();
  closeMixer();
  ua?.stop();
  ua = null;
  releaseLock?.();
  releaseLock = null;
  clearTimeout(endedTimer);
  phone.call = null;
};

const connect = async () => {
  const current = generation;
  phone.status = 'connecting';
  JsSIP = JsSIP || (await import('jssip')).default;
  if (current !== generation) return;
  ua = new JsSIP.UA({
    sockets: [new JsSIP.WebSocketInterface(config.ws_url)],
    uri: `sip:${config.extension}@${config.domain}`,
    password: config.password,
    display_name: config.name,
    session_timers: false,
    user_agent: 'Outsider CRM',
  });
  ua.on('registered', () => {
    phone.status = 'ready';
  });
  ua.on('disconnected', () => {
    if (current === generation) phone.status = 'offline';
  });
  ua.on('registrationFailed', () => {
    if (current !== generation) return;
    phone.status = 'failed';
    setTimeout(() => {
      if (current === generation) ua.register();
    }, CENTRAL_SYNC_WAIT);
  });
  ua.on('newRTCSession', onSession);
  ua.start();
};

// --- abas: quem está com a linha manda o estado; as outras mandam os pedidos ---

const snapshot = () => {
  const { holder, notice, ...state } = phone;
  return JSON.parse(JSON.stringify(state));
};

const publish = () => {
  if (phone.holder) channel?.postMessage({ type: 'state', state: snapshot() });
};

// muda muito durante a ligação (barras, tempo não: são calculados em cada aba); junta num aviso só
let publishQueued = false;
watch(
  () => phone,
  () => {
    if (!phone.holder || publishQueued) return;
    publishQueued = true;
    queueMicrotask(() => {
      publishQueued = false;
      publish();
    });
  },
  { deep: true }
);
// o aviso vai à parte: cada aba mostra o seu
watch(
  () => phone.notice,
  notice => {
    if (phone.holder && notice) {
      channel?.postMessage({ type: 'notice', notice: { ...notice } });
    }
  }
);

const remote = (name, ...args) => {
  channel?.postMessage({ type: 'command', name, args });
  return null;
};

let handshake = null;

const onChannelMessage = ({ data }) => {
  if (!data) return;
  if (data.type === 'hello' && phone.holder) publish();
  else if (data.type === 'state' && !phone.holder) {
    Object.assign(phone, data.state);
    handshake?.(data.state);
  } else if (data.type === 'notice' && !phone.holder)
    phone.notice = data.notice;
  else if (data.type === 'bye' && !phone.holder) {
    phone.call = null;
    phone.popout = false;
    phone.status = 'other_tab';
  } else if (data.type === 'command' && phone.holder) {
    // eslint-disable-next-line no-use-before-define
    COMMANDS[data.name]?.(...(data.args || []));
  }
};

const openChannel = key => {
  channel?.close();
  channel =
    'BroadcastChannel' in window
      ? new BroadcastChannel(`outsider-phone-${key}`)
      : null;
  if (channel) channel.onmessage = onChannelMessage;
};

const becomeMirror = () => {
  phone.holder = false;
  phone.status = 'other_tab';
  channel?.postMessage({ type: 'hello' });
};

// mode: try (só se nenhuma aba estiver com o telefone), wait (assume quando a outra aba fechar) ou steal
const requestLine = (key, mode) => {
  if (!navigator.locks) {
    phone.holder = true;
    connect();
    return;
  }
  waiting?.abort();
  waiting = mode === 'wait' ? new AbortController() : null;
  const options = {
    try: { ifAvailable: true },
    wait: { signal: waiting?.signal },
    steal: { steal: true },
  }[mode];
  let held = false;
  navigator.locks
    .request(`outsider-phone-${key}`, options, lock => {
      if (accountKey !== key) return undefined;
      if (!lock) {
        becomeMirror();
        requestLine(key, 'wait');
        return undefined;
      }
      held = true;
      waiting = null;
      phone.holder = true;
      phone.popout = asPopout;
      phone.call = null;
      connect();
      return new Promise(resolve => {
        releaseLock = resolve;
      });
    })
    .catch(() => {
      // outra aba trouxe o telefone para ela ("usar nesta aba")
      if (!held || accountKey !== key) return;
      disconnect();
      if (asPopout) {
        window.close();
        return;
      }
      becomeMirror();
      requestLine(key, 'wait');
    });
};

const sayGoodbye = () => {
  if (phone.holder) channel?.postMessage({ type: 'bye' });
};
window.addEventListener('pagehide', sayGoodbye);

export const stopPhone = () => {
  sayGoodbye();
  accountKey = null;
  waiting?.abort();
  waiting = null;
  disconnect();
  channel?.close();
  channel = null;
  phone.holder = false;
  phone.popout = false;
  phone.status = 'off';
};

// popout: a janela própria do telefone, que traz a linha para ela (se não houver ligação em outra aba)
export const startPhone = async (accountId, { popout = false } = {}) => {
  if (accountKey === accountId) return;
  stopPhone();
  accountKey = accountId;
  asPopout = popout;
  let data;
  try {
    ({ data } = await VoiceAPI.me());
  } catch {
    return;
  }
  if (accountKey !== accountId || !data.enabled) return;
  config = { ...data, domain: new URL(data.ws_url).hostname };
  phone.extension = data.extension;
  phone.echoExtension = data.echo_extension;
  phone.recordingAllowed = !!data.recording;
  openChannel(accountId);
  if (!popout) {
    requestLine(accountId, 'try');
    return;
  }
  const state = await new Promise(resolve => {
    handshake = resolve;
    channel?.postMessage({ type: 'hello' });
    setTimeout(resolve, POPOUT_HANDSHAKE);
  });
  handshake = null;
  if (accountKey !== accountId) return;
  const busy = state?.call && state.call.state !== 'ended';
  if (busy) {
    becomeMirror();
    requestLine(accountId, 'wait');
  } else requestLine(accountId, 'steal');
};

// de novo do zero (ramal ou senha podem ter mudado nas Configurações); nunca no meio de uma ligação
export const restartPhone = () => {
  if (phone.call && phone.call.state !== 'ended') return;
  const accountId = accountKey;
  const popout = asPopout;
  stopPhone();
  startPhone(accountId, { popout });
};

export const useThisTab = () => {
  if (accountKey) requestLine(accountKey, 'steal');
};

// --- janela própria do telefone ---

export const openPopout = accountId => {
  if (phone.call && phone.call.state !== 'ended') return 'IN_CALL';
  popoutRef = window.open(
    frontendURL(`accounts/${accountId}/telefone`),
    POPOUT_NAME,
    POPOUT_FEATURES
  );
  if (!popoutRef) return 'POPUP_BLOCKED';
  setPanelOpen(false);
  return null;
};

const focusWindow = () => window.focus();

export const isPopoutWindow = () => asPopout;

export const showPopout = () => {
  if (popoutRef && !popoutRef.closed) popoutRef.focus();
  else remote('focusWindow');
};

// --- o que as telas chamam ---

// número de cliente (com ou sem +55, máscara, espaços) ou ramal; devolve o motivo quando não dá
export const dial = number => {
  const target = digitsOf(number);
  if (phone.status === 'other_tab') return 'OTHER_TAB';
  if (phone.status !== 'ready') return 'NOT_READY';
  if (phone.call && phone.call.state !== 'ended') return 'IN_CALL';
  if (!target) return 'INVALID';
  if (!phone.holder) return remote('dial', target);
  outgoing = { id: nextId, number: target };
  nextId += 1;
  ua.call(`sip:${target}@${config.domain}`, {
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
  });
  return null;
};

export const answer = () => {
  if (phone.call?.state !== 'ringing') return null;
  if (!phone.holder) return remote('answer');
  stopTone();
  mainLeg()?.session.answer({
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
  });
  return null;
};

// recusar só tira esta pessoa: a central segue tocando para os outros. Na conferência, desliga todo mundo
export const hangup = () => {
  if (!phone.call || phone.call.state === 'ended') return null;
  if (!phone.holder) return remote('hangup');
  const main = mainLeg();
  if (phone.call.state === 'ringing') {
    if (!main.session.isEnded()) main.session.terminate({ status_code: 486 });
    return null;
  }
  [...phone.call.others.map(other => other.id), phone.call.id].forEach(id => {
    const session = legs.get(id)?.session;
    if (session && !session.isEnded()) session.terminate();
  });
  return null;
};

// mudo desliga o microfone em todas as ligações (na conferência ninguém ouve você; os outros se ouvem)
export const toggleMute = () => {
  if (phone.call?.state !== 'active') return null;
  if (!phone.holder) return remote('toggleMute');
  const muted = !phone.call.muted;
  phone.call.muted = muted;
  legs.forEach(leg => {
    if (leg.micTrack) leg.micTrack.enabled = !muted;
  });
  return null;
};

export const sendDigit = digit => {
  if (phone.call?.state !== 'active') return null;
  if (!phone.holder) return remote('sendDigit', digit);
  mainLeg()?.session.sendDTMF(digit, { transportType: 'RFC2833' });
  return null;
};

export const clearEndedCall = () => {
  if (phone.call?.state !== 'ended') return null;
  if (!phone.holder) return remote('clearEndedCall');
  phone.call = null;
  return null;
};

export const inConference = () =>
  !!phone.call?.others.some(other => other.state !== 'ended');

// espera: o outro lado fica em silêncio até voltar (Entrega 23); não vale na conferência
export const toggleHold = () => {
  if (phone.call?.state !== 'active' || inConference()) return null;
  if (!phone.holder) return remote('toggleHold');
  const { session } = mainLeg();
  if (phone.call.held) session.unhold();
  else session.hold();
  phone.call.held = !phone.call.held;
  return null;
};

// transferência direta para outro ramal: a central liga para ele e, quando confirma, esta ligação acaba aqui
export const transfer = extension => {
  if (
    phone.call?.state !== 'active' ||
    inConference() ||
    !/^\d{3}$/.test(extension)
  ) {
    return null;
  }
  if (!phone.holder) return remote('transfer', extension);
  phone.call.transferTo = extension;
  const { session: current } = mainLeg();
  current.refer(`sip:${extension}@${config.domain}`, {
    eventHandlers: {
      accepted: () => {
        if (!current.isEnded()) current.terminate();
      },
      requestFailed: () => {
        if (phone.call) phone.call.transferTo = '';
      },
      failed: () => {
        if (phone.call) phone.call.transferTo = '';
      },
    },
  });
  return null;
};

// conferência: liga para mais uma pessoa (ramal ou número) sem desligar a ligação atual; quando ela atende,
// entra na conversa
export const addToConference = number => {
  const target = digitsOf(number);
  const call = phone.call;
  if (call?.state !== 'active') return 'NOT_READY';
  if (!target || target === phone.extension) return 'INVALID';
  const others = call.others.filter(other => other.state !== 'ended');
  if (others.length >= MAX_GUESTS) return 'CONFERENCE_FULL';
  if ([call.number, ...others.map(other => other.number)].includes(target)) {
    return 'ALREADY_IN_CALL';
  }
  if (!phone.holder) return remote('addToConference', target);
  if (call.held) toggleHold();
  outgoing = { id: nextId, number: target, guest: true };
  nextId += 1;
  ua.call(`sip:${target}@${config.domain}`, {
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
  });
  return null;
};

// tira uma pessoa da conferência (só ela desliga)
export const removeFromConference = id => {
  if (!phone.holder) return remote('removeFromConference', id);
  const session = legs.get(id)?.session;
  if (session && !session.isEnded()) session.terminate();
  return null;
};

// gravar: começa a gravar; depois, pausa e continua. O arquivo vai para a ligação quando ela acaba
export const toggleRecording = () => {
  if (phone.call?.state !== 'active' || !phone.recordingAllowed) return null;
  if (!phone.holder) return remote('toggleRecording');
  if (!recorder && !canRecord()) return null;
  if (!recorder) {
    const type = RECORDING_TYPES.find(item =>
      window.MediaRecorder?.isTypeSupported(item)
    );
    if (!type) {
      notify('RECORDING_UNSUPPORTED');
      return null;
    }
    const { record } = ensureMixer();
    const media = new MediaRecorder(record.stream, {
      mimeType: type,
      audioBitsPerSecond: RECORDING_BITRATE,
    });
    recorder = {
      media,
      chunks: [],
      // todos que passaram pela ligação enquanto gravava (quem saiu da conferência também)
      parties: new Map(callParties().map(party => [party.number, party])),
    };
    const { chunks } = recorder;
    media.ondataavailable = event => {
      if (event.data.size) chunks.push(event.data);
    };
    media.start(1000);
    phone.call.recording = 'on';
    remix();
    return null;
  }
  if (recorder.media.state === 'recording') {
    recorder.media.pause();
    phone.call.recording = 'paused';
  } else {
    recorder.media.resume();
    phone.call.recording = 'on';
  }
  return null;
};

// áudio de uma ligação (o microfone da pessoa e o som do outro lado), para as barras que mexem com a voz;
// só na aba que está com a linha
export const callStreams = (id = phone.call?.id) => {
  const leg = legs.get(id);
  return {
    local: leg?.micTrack ? new MediaStream([leg.micTrack]) : null,
    remote: leg?.remote || null,
  };
};

const COMMANDS = {
  dial,
  answer,
  hangup,
  toggleMute,
  toggleHold,
  transfer,
  sendDigit,
  clearEndedCall,
  addToConference,
  removeFromConference,
  toggleRecording,
  focusWindow,
};
