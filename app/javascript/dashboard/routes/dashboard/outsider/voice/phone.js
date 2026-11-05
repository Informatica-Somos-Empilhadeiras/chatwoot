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
// Entrega 26: ligação pelo negócio (vai junto para a central, que vincula a ligação a ele), monitoria do
// supervisor (*80 ouve sem ninguém perceber; *81 entra sussurrando) e sussurro de colega convidado. Quem
// sussurra entra como uma ligação a mais no telefone do atendente (call.whispers): a mistura daqui manda a voz
// dele só para o atendente e os ramais da conferência; o cliente só ouve quando o sussurro fica aberto
// (supervisor abre quando quer; convidado precisa da permissão do atendente). Os avisos entre os telefones
// passam pelo Chatwoot (VoiceAPI.signal), que confere quem pode o quê.
//
// O estado fica em `phone` (reativo): as telas leem; para agir, chamam as funções exportadas.
import { reactive, watch } from 'vue';
import VoiceAPI from 'dashboard/api/outsider/voice';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { startTone, stopTone } from './ringtone';
import { formatPhone } from './format';

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
// gravação em qualidade de voz baixa, mono (Entrega 25): uns 7 MB por hora de conversa
const RECORDING_BITRATE = 16000;
const RECORDING_TYPES = [
  'audio/webm;codecs=opus',
  'audio/ogg;codecs=opus',
  'audio/webm',
];
const POPOUT_NAME = 'outsider-phone';
const POPOUT_FEATURES = 'popup,width=400,height=760';
// a janela própria espera um pouco a resposta das abas antes de tomar a linha (para não derrubar ligação)
const POPOUT_HANDSHAKE = 400;
// convite para entrar na ligação vale 2 minutos (o mesmo prazo do servidor); toca por até 30 s
const INVITE_VISIBLE = 120000;
const INVITE_RING = 30000;
// quem entra pela central: "supervisor:<id>:whisper" ou "guest:<id>:open|whisper" (como foi convidado)
const WHISPER_HEADER = /^(supervisor|guest):(\d+)(?::(open|whisper))?$/;
export const MONITOR_PREFIX = { listen: '*80', whisper: '*81' };

// status: off (sem telefone: telefonia ou ramal desligados), connecting, ready, offline (sem conexão com a
// central), failed (a central recusou o ramal) ou other_tab (outra aba está com a linha e não respondeu)
// holder: esta aba está com a linha; popout: a linha está na janela própria do telefone
// call.others: as pessoas incluídas na conferência; notice: aviso para as telas (gravação salva...)
// call.whispers: quem está sussurrando nesta ligação; call.monitor: esta ligação é uma monitoria (ouvir ou
// sussurrar na ligação de outra pessoa); invite: convite de um colega para sussurrar na ligação dele
export const phone = reactive({
  status: 'off',
  extension: '',
  echoExtension: '',
  recordingAllowed: false,
  autoRecord: false,
  supervisor: false,
  userId: null,
  call: null,
  holder: false,
  popout: false,
  notice: null,
  invite: null,
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
let inviteTimer = null;
let inviteRingTimer = null;
let inviteRinging = false;
// supervisor que estava ouvindo e passou a sussurrar: a ligação nova sai assim que a de ouvir acaba
let relaunch = null;

const digitsOf = value => String(value || '').replace(/\D/g, '');

const notify = (code, params = {}) => {
  phone.notice = { code, params, at: Date.now() };
};

const legState = id => {
  if (!phone.call) return null;
  if (phone.call.id === id) return phone.call;
  return (
    phone.call.others.find(other => other.id === id) ||
    phone.call.whispers.find(whisper => whisper.id === id) ||
    null
  );
};

const isWhisper = id => !!phone.call?.whispers.some(item => item.id === id);

const mainLeg = () => phone.call && legs.get(phone.call.id);

const audioSender = session =>
  session?.connection
    ?.getSenders()
    .find(sender => sender.track?.kind === 'audio');

// monitoria que não chegou a entrar (Entrega 26d): o motivo diz onde está o problema. "Não encontrado" é a central
// sem os códigos *80/*81 (plano de discagem antigo); recusa (503) é o Chatwoot negando a permissão; ocupado é o
// telefone do atendente sem ligação atendida
const monitorReason = ({ cause }) => {
  const { causes } = JsSIP.C;
  if ([causes.NOT_FOUND, causes.ADDRESS_INCOMPLETE].includes(cause)) {
    return 'MONITOR_OUTDATED';
  }
  if (cause === causes.BUSY) return 'MONITOR_BUSY';
  if ([causes.UNAVAILABLE, causes.NO_ANSWER].includes(cause)) {
    return 'MONITOR_UNAVAILABLE';
  }
  if ([causes.SIP_FAILURE_CODE, causes.REJECTED].includes(cause)) {
    return 'MONITOR_REFUSED';
  }
  // sem conexão com a central e afins: o motivo de sempre
  return null;
};

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

// --- mistura do áudio (conferência, sussurro e gravação) ---

// [{ leg, state }] das ligações em conversa: as pessoas (a principal e a conferência) ou quem sussurra
const activePairs = list =>
  list
    .filter(state => state.state === 'active' && legs.has(state.id))
    .map(state => ({ leg: legs.get(state.id), state }));

const activeParties = () =>
  phone.call ? activePairs([phone.call, ...phone.call.others]) : [];

const activeWhispers = () =>
  phone.call ? activePairs(phone.call.whispers) : [];

const closeMixer = () => {
  mixer?.context.close().catch(() => {});
  mixer = null;
};

const ensureMixer = () => {
  if (!mixer) {
    const context = new AudioContext();
    const record = context.createMediaStreamDestination();
    record.channelCount = 1;
    record.channelCountMode = 'explicit';
    mixer = { context, record, nodes: [] };
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

const sendMix = leg => {
  const sender = audioSender(leg.session);
  const [track] = leg.dest.stream.getAudioTracks();
  if (sender && sender.track !== track) sender.replaceTrack(track);
};

// refeita a cada pessoa que entra ou sai: cada ligação recebe o seu microfone e o som das outras. Quem sussurra
// ouve todo mundo; a voz dele vai para os ramais (atendentes) e, só com o sussurro aberto, para o cliente e a
// gravação (a gravação pode ser encaminhada ao cliente)
const remix = () => {
  const parties = activeParties();
  const whispers = activeWhispers();
  const mixing = parties.length > 1 || whispers.length > 0;
  if (!mixing && !recorder) {
    useOwnMicrophone(parties.map(({ leg }) => leg));
    return;
  }
  const { context, record } = ensureMixer();
  mixer.nodes.forEach(node => node.disconnect());
  const micTrack = [...parties, ...whispers].find(({ leg }) => leg.micTrack)
    ?.leg.micTrack;
  const mic = micTrack
    ? context.createMediaStreamSource(new MediaStream([micTrack]))
    : null;
  const sourceOf = ({ leg }) =>
    leg.remote?.getAudioTracks().length
      ? context.createMediaStreamSource(leg.remote)
      : null;
  const partyRemotes = parties.map(sourceOf);
  const whisperRemotes = whispers.map(sourceOf);
  const open = index => whispers[index].state.mode === 'open';
  mixer.nodes = [mic, ...partyRemotes, ...whisperRemotes].filter(Boolean);
  if (recorder) {
    [mic, ...partyRemotes, ...whisperRemotes.filter((_, index) => open(index))]
      .filter(Boolean)
      .forEach(node => node.connect(record));
    callParties().forEach(party => recorder.parties.set(party.number, party));
  }
  if (!mixing) {
    useOwnMicrophone(parties.map(({ leg }) => leg));
    return;
  }
  parties.forEach(({ leg, state }, index) => {
    leg.dest = leg.dest || context.createMediaStreamDestination();
    mic?.connect(leg.dest);
    partyRemotes.forEach((remote, other) => {
      if (other !== index) remote?.connect(leg.dest);
    });
    whisperRemotes.forEach((remote, other) => {
      if (open(other) || !isExternal(state.number)) remote?.connect(leg.dest);
    });
    sendMix(leg);
  });
  whispers.forEach(({ leg }, index) => {
    leg.dest = leg.dest || context.createMediaStreamDestination();
    mic?.connect(leg.dest);
    partyRemotes.forEach(remote => remote?.connect(leg.dest));
    whisperRemotes.forEach((remote, other) => {
      if (other !== index) remote?.connect(leg.dest);
    });
    sendMix(leg);
  });
};

// --- gravação ---

// grava só com cliente na ligação: a gravação fica na ligação dele, em Telefonia > Ligações. Monitoria não grava
export const canRecord = () =>
  !!phone.call &&
  !phone.call.monitor &&
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
    if (state?.number !== number) return;
    state.lookup = data;
    // o negócio que a central ligou à ligação (o aberto do cliente), se ela não saiu de um negócio escolhido
    if (state.id === phone.call?.id && !state.deal && data.deal) {
      state.deal = { id: data.deal.id, title: data.deal.title };
    }
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
  // Entrega 26: o negócio vinculado, quem sussurra e se é uma monitoria
  deal: null,
  whispers: [],
  monitor: null,
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
  [...call.others, ...call.whispers].forEach(other => {
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
  if (relaunch) {
    const next = relaunch;
    relaunch = null;
    // eslint-disable-next-line no-use-before-define
    setTimeout(() => monitorCall(next, 'whisper'), 300);
  }
};

// a primeira ligação acabou e ainda tem gente na conferência: a próxima pessoa vira a principal
const promote = guest => {
  const { others, muted, recording, startedAt, whispers } = phone.call;
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
    whispers,
  };
};

const endLeg = (id, reason) => {
  const leg = legs.get(id);
  if (!leg || !phone.call) return;
  legs.delete(id);
  leg.audio.srcObject = null;
  if (isWhisper(id)) {
    const whisper = legState(id);
    whisper.state = 'ended';
    whisper.request = false;
    setTimeout(() => {
      if (phone.call) {
        phone.call.whispers = phone.call.whispers.filter(
          item => item.id !== id
        );
      }
    }, GUEST_ENDED_VISIBLE);
    remix();
    return;
  }
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
    // ouvir em silêncio: o microfone do supervisor fica desligado (a central também não passa a voz dele)
    if (phone.call.monitor?.mode === 'listen') phone.call.muted = true;
    if (leg.micTrack && phone.call.muted) leg.micTrack.enabled = false;
    remix();
    // eslint-disable-next-line no-use-before-define
    autoRecord();
  });
  current.on('ended', event => endLeg(id, endReason(event)));
  current.on('failed', event => {
    const monitoring =
      phone.call?.id === id &&
      phone.call.monitor &&
      event.originator !== 'local';
    endLeg(id, (monitoring && monitorReason(event)) || endReason(event));
  });
};

// alguém entrando na ligação em andamento: o telefone atende sozinho (a central só manda depois de conferir que é
// o supervisor do atendente ou um colega convidado por ele). Supervisor entra sussurrando; o colega, falando com o
// cliente (open) ou só com o atendente (whisper), como foi convidado
const acceptWhisper = (current, request, header) => {
  const [, kind, userId, start] = header.match(WHISPER_HEADER);
  const id = nextId;
  nextId += 1;
  phone.call.whispers.push({
    id,
    kind,
    userId: Number(userId),
    name: request.from.display_name || request.from.uri.user || '',
    state: 'ringing',
    mode: kind === 'guest' && start === 'open' ? 'open' : 'whisper',
    request: false,
    answeredAt: null,
    endReason: '',
  });
  setupLeg(id, current);
  current.answer({
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
  });
  let notice = 'GUEST_JOINED';
  if (kind === 'supervisor') notice = 'SUPERVISOR_JOINED';
  else if (start === 'open') notice = 'GUEST_JOINED_OPEN';
  notify(notice, { name: request.from.display_name || '' });
};

const onSession = ({ session: current, originator, request }) => {
  // ligação nova: o toque passa a ser dela (o do convite não pode mais parar o som dela)
  clearTimeout(inviteRingTimer);
  inviteRinging = false;
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
      phone.call = {
        ...newCall({
          id: target.id,
          direction: 'outbound',
          number: target.number,
          name: target.monitor?.name || '',
          state: 'dialing',
        }),
        deal: target.deal || null,
        monitor: target.monitor || null,
      };
    }
    setupLeg(target.id, current);
    if (!target.monitor) lookup(target.id, target.number);
    return;
  }
  const whisper = request.getHeader('X-Outsider-Whisper') || '';
  if (
    WHISPER_HEADER.test(whisper) &&
    phone.call?.state === 'active' &&
    !phone.call.monitor
  ) {
    acceptWhisper(current, request, whisper);
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
  relaunch = null;
  inviteRinging = false;
  clearTimeout(inviteRingTimer);
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
  phone.supervisor = !!data.supervisor;
  phone.userId = data.user_id;
  phone.recordingAllowed = !!data.recording;
  phone.autoRecord = !!data.auto_record;
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

const canDial = () => {
  if (phone.status === 'other_tab') return 'OTHER_TAB';
  if (phone.status !== 'ready') return 'NOT_READY';
  if (phone.call && phone.call.state !== 'ended') return 'IN_CALL';
  return null;
};

// número de cliente (com ou sem +55, máscara, espaços) ou ramal; devolve o motivo quando não dá.
// deal ({ id, title }): ligação feita pelo negócio, que vai junto para a central vincular (Entrega 26)
export const dial = (number, { deal = null } = {}) => {
  const target = digitsOf(number);
  const blocked = canDial();
  if (blocked) return blocked;
  if (!target) return 'INVALID';
  if (!phone.holder) return remote('dial', target, { deal });
  const dealId = Number(deal?.id) || null;
  outgoing = {
    id: nextId,
    number: target,
    deal: dealId ? { id: dealId, title: deal.title || '' } : null,
  };
  nextId += 1;
  ua.call(`sip:${target}@${config.domain}`, {
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
    extraHeaders: dealId ? [`X-Outsider-Deal: ${dealId}`] : [],
  });
  return null;
};

// monitoria (Entrega 26): mode listen (ouvir sem ninguém perceber) ou whisper (sussurrar). target: { extension,
// userId, name, customer, kind } do atendente (kind guest quando é um colega que convidou)
export const monitorCall = (target, mode) => {
  const blocked = canDial();
  if (blocked) return blocked;
  if (!/^[1-5]\d{2}$/.test(target?.extension || '') || !MONITOR_PREFIX[mode]) {
    return 'INVALID';
  }
  if (!phone.holder) return remote('monitorCall', target, mode);
  const number = `${MONITOR_PREFIX[mode]}${target.extension}`;
  outgoing = {
    id: nextId,
    number,
    monitor: {
      mode,
      kind: target.kind || 'supervisor',
      extension: target.extension,
      userId: target.userId,
      name: target.name || '',
      customer: target.customer || '',
      open: !!target.open,
      pending: false,
    },
  };
  nextId += 1;
  ua.call(`sip:${number}@${config.domain}`, {
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
  });
  return null;
};

// supervisor ouvindo passa a sussurrar: sai da escuta e entra de novo, agora como sussurro (o atendente percebe)
export const switchToWhisper = () => {
  const monitor = phone.call?.monitor;
  if (monitor?.mode !== 'listen' || phone.call.state !== 'active') return null;
  if (!phone.holder) return remote('switchToWhisper');
  relaunch = { ...monitor };
  mainLeg()?.session.terminate();
  return null;
};

const signal = async (type, toUserId, data = {}) => {
  try {
    await VoiceAPI.signal(type, toUserId, data);
    return true;
  } catch {
    notify('SIGNAL_FAILED');
    return false;
  }
};

// quem sussurra pede para o cliente ouvir (open) ou volta a falar só com os atendentes (whisper). Supervisor
// abre na hora; o convidado espera o atendente permitir
export const requestWhisperMode = async mode => {
  const monitor = phone.call?.monitor;
  if (monitor?.mode !== 'whisper' || phone.call.state !== 'active') return;
  if (!phone.holder) {
    remote('requestWhisperMode', mode);
    return;
  }
  monitor.pending = mode === 'open' && monitor.kind === 'guest';
  const sent = await signal('request_mode', monitor.userId, { mode });
  if (!sent && phone.call?.monitor) phone.call.monitor.pending = false;
};

// atendente: o cliente passa a ouvir (open) ou deixa de ouvir (whisper) quem sussurra; approved false recusa o
// pedido do convidado. Sussurro do supervisor só ele mesmo abre ou fecha
export const setWhisperMode = (id, mode, approved = true) => {
  const whisper = phone.call?.whispers.find(item => item.id === id);
  if (!whisper || whisper.state === 'ended') return null;
  if (whisper.kind === 'supervisor') return null;
  if (!phone.holder) return remote('setWhisperMode', id, mode, approved);
  whisper.mode = approved ? mode : 'whisper';
  whisper.request = false;
  remix();
  signal('mode', whisper.userId, { mode: whisper.mode, approved });
  return null;
};

// atendente convida um colega (com ramal) para esta ligação: mode open (fala com o cliente junto) ou whisper (só
// com o atendente; para o cliente ouvir, o atendente permite depois)
export const inviteToCall = async (person, mode = 'open') => {
  if (phone.call?.state !== 'active' || phone.call.monitor) return;
  const customer =
    phone.call.lookup?.contact?.name || formatPhone(phone.call.number);
  if (await signal('invite', person.id, { customer, mode })) {
    notify('INVITE_SENT', { name: person.name });
  }
};

const stopInviteRing = () => {
  clearTimeout(inviteRingTimer);
  if (inviteRinging) stopTone();
  inviteRinging = false;
};

const clearInvite = () => {
  phone.invite = null;
  clearTimeout(inviteTimer);
  stopInviteRing();
};

export const acceptInvite = () => {
  const invite = phone.invite;
  if (!invite) return null;
  if (!phone.holder) return remote('acceptInvite');
  const blocked = canDial();
  if (blocked) return blocked;
  clearInvite();
  return monitorCall(
    {
      extension: invite.extension,
      userId: invite.userId,
      name: invite.name,
      customer: invite.customer,
      kind: 'guest',
      open: invite.mode === 'open',
    },
    'whisper'
  );
};

export const declineInvite = () => {
  const invite = phone.invite;
  if (!invite) return null;
  if (!phone.holder) return remote('declineInvite');
  clearInvite();
  signal('invite_declined', invite.userId);
  return null;
};

// avisos de outros telefones (Outsider::Voice::Signals), entregues pelo canal ao vivo; só quem está com a linha age
export const handleSignal = data => {
  if (!phone.holder || !data?.type) return;
  const from = data.from || {};
  const whisper = phone.call?.whispers.find(
    item => item.userId === from.id && item.state !== 'ended'
  );
  if (data.type === 'invite') {
    clearInvite();
    phone.invite = {
      userId: from.id,
      name: from.name,
      extension: data.extension,
      customer: data.customer,
      mode: data.mode === 'whisper' ? 'whisper' : 'open',
      at: Date.now(),
    };
    inviteTimer = setTimeout(clearInvite, INVITE_VISIBLE);
    // toca como ligação chegando, menos se a pessoa já estiver numa ligação
    if (!phone.call || phone.call.state === 'ended') {
      inviteRinging = true;
      startTone('incoming');
      inviteRingTimer = setTimeout(stopInviteRing, INVITE_RING);
    }
  } else if (data.type === 'invite_declined') {
    notify('INVITE_DECLINED', { name: from.name });
  } else if (data.type === 'apply_mode' && whisper) {
    whisper.mode = data.mode === 'open' ? 'open' : 'whisper';
    whisper.request = false;
    remix();
    signal('mode', whisper.userId, { mode: whisper.mode, approved: true });
  } else if (data.type === 'mode_request' && whisper) {
    whisper.request = true;
    notify('WHISPER_REQUEST', { name: whisper.name });
  } else if (data.type === 'mode') {
    const monitor = phone.call?.monitor;
    if (!monitor || monitor.userId !== from.id) return;
    monitor.open = data.mode === 'open';
    monitor.pending = false;
    if (data.approved === false) notify('WHISPER_REFUSED');
  }
};

// negócio vinculado à ligação em andamento (ou que acabou de acabar); deal null desvincula
export const linkCallDeal = async deal => {
  const call = phone.call;
  if (!call || call.monitor) return 'NOT_READY';
  try {
    await VoiceAPI.updateCall(call.number, call.startedAt, {
      opportunity_id: deal?.id || '',
    });
  } catch {
    return 'LINK_FAILED';
  }
  // eslint-disable-next-line no-use-before-define
  setCallDeal(deal ? { id: deal.id, title: deal.title } : null);
  return null;
};

export const setCallDeal = deal => {
  if (!phone.call) return null;
  if (!phone.holder) return remote('setCallDeal', deal);
  phone.call.deal = deal;
  return null;
};

// cadastro do cliente criado durante a ligação: liga à ligação e busca de novo quem é
export const linkCallContact = async contactId => {
  const call = phone.call;
  if (!call) return 'NOT_READY';
  try {
    await VoiceAPI.updateCall(call.number, call.startedAt, {
      contact_id: contactId,
    });
  } catch {
    return 'LINK_FAILED';
  }
  // eslint-disable-next-line no-use-before-define
  refreshLookup();
  return null;
};

export const refreshLookup = () => {
  if (!phone.call) return null;
  if (!phone.holder) return remote('refreshLookup');
  lookup(phone.call.id, phone.call.number);
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
  [
    ...phone.call.whispers.map(whisper => whisper.id),
    ...phone.call.others.map(other => other.id),
    phone.call.id,
  ].forEach(id => {
    const session = legs.get(id)?.session;
    if (session && !session.isEnded()) session.terminate();
  });
  return null;
};

// mudo desliga o microfone em todas as ligações (na conferência ninguém ouve você; os outros se ouvem)
export const toggleMute = () => {
  if (phone.call?.state !== 'active' || phone.call.monitor?.mode === 'listen') {
    return null;
  }
  if (!phone.holder) return remote('toggleMute');
  const muted = !phone.call.muted;
  phone.call.muted = muted;
  legs.forEach(leg => {
    if (leg.micTrack) leg.micTrack.enabled = !muted;
  });
  return null;
};

export const sendDigit = digit => {
  if (phone.call?.state !== 'active' || phone.call.monitor) return null;
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
  if (phone.call?.state !== 'active' || inConference() || phone.call.monitor) {
    return null;
  }
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
    phone.call.monitor ||
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
  if (call?.state !== 'active' || call.monitor) return 'NOT_READY';
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

const startRecorder = () => {
  const type = RECORDING_TYPES.find(item =>
    window.MediaRecorder?.isTypeSupported(item)
  );
  if (!type) {
    notify('RECORDING_UNSUPPORTED');
    return;
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
};

// gravação automática (Telefonia > Configurações, Entrega 25): começa quando a ligação com cliente é atendida
// (ou quando um cliente entra na conferência), só na aba que está com a linha
function autoRecord() {
  if (!phone.autoRecord || !phone.holder || recorder) return;
  if (phone.call?.state !== 'active' || !canRecord()) return;
  startRecorder();
}

// gravar: começa a gravar; depois, pausa e continua. O arquivo vai para a ligação quando ela acaba
export const toggleRecording = () => {
  if (phone.call?.state !== 'active' || !phone.recordingAllowed) return null;
  if (!phone.holder) return remote('toggleRecording');
  if (!recorder && !canRecord()) return null;
  if (!recorder) {
    startRecorder();
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

// aviso do navegador quando toca com a aba escondida: pede a permissão num clique da pessoa (atender,
// abrir o telefone), porque o navegador não deixa pedir sozinho
export const askNotifications = () => {
  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission().catch(() => {});
  }
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
  monitorCall,
  switchToWhisper,
  requestWhisperMode,
  setWhisperMode,
  acceptInvite,
  declineInvite,
  setCallDeal,
  refreshLookup,
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
