// OUTSIDER: o telefone do navegador (Entrega 22). Entra na central (Asterisk) com o ramal da pessoa, pela
// conexão WebSocket da central (JsSIP), e faz e recebe ligações com o microfone e o fone do computador.
//
// Só uma aba por navegador fica com o telefone (Web Locks): as outras mostram "em uso em outra aba", com a
// opção de trazer para a aba atual; ao fechar a aba que estava com ele, a próxima assume sozinha.
// O estado fica em `phone` (reativo): as telas leem; para agir, chamam as funções exportadas.
import { reactive } from 'vue';
import VoiceAPI from 'dashboard/api/outsider/voice';
import { startTone, stopTone } from './ringtone';

const ICE_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }];
// a ligação sai com os endereços que o navegador achou até aqui (o endereço público vem do STUN)
const ICE_WAIT = 1500;
// "Ocupado", "Não atendeu"... ficam na tela por um tempo depois que a ligação acaba
const ENDED_VISIBLE = 4000;
// ramal recém-ligado nas Configurações: a central só o conhece depois de buscar a configuração (até 30 s)
export const CENTRAL_SYNC_WAIT = 35000;
const MEDIA = { audio: true, video: false };

// status: off (sem telefone: telefonia ou ramal desligados), connecting, ready, offline (sem conexão com a
// central), failed (a central recusou o ramal) ou other_tab
export const phone = reactive({
  status: 'off',
  extension: '',
  echoExtension: '',
  call: null,
});

// painel do telefone aberto (fixo na tela) ou minimizado; guardado no navegador (Entrega 23)
const PANEL_KEY = 'outsider_phone_panel';
const readPanel = () => {
  try {
    return localStorage.getItem(PANEL_KEY) === 'open';
  } catch {
    return false;
  }
};
export const panel = reactive({ open: readPanel() });

export const setPanelOpen = open => {
  panel.open = open;
  try {
    localStorage.setItem(PANEL_KEY, open ? 'open' : 'closed');
  } catch {
    // sem localStorage o painel só não lembra como estava
  }
};

let JsSIP = null;
let config = null;
let accountKey = null;
let ua = null;
let session = null;
let dialing = null;
let releaseLock = null;
let waiting = null;
let generation = 0;
let endedTimer = null;
const remoteAudio = new Audio();
remoteAudio.autoplay = true;

const playRemote = connection => {
  connection.addEventListener('track', event => {
    [remoteAudio.srcObject] = event.streams;
  });
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

const finish = (current, reason) => {
  if (current !== session) return;
  stopTone();
  session = null;
  remoteAudio.srcObject = null;
  phone.call.state = 'ended';
  // ramal "indisponível": a pessoa não está com o telefone aberto (ou o ramal está desligado)
  const toExtension = phone.call.number.length <= 4;
  if (phone.call.transferTo) phone.call.endReason = 'TRANSFERRED';
  else if (reason === 'UNAVAILABLE' && toExtension) {
    phone.call.endReason = 'EXTENSION_OFFLINE';
  } else phone.call.endReason = reason;
  endedTimer = setTimeout(() => {
    if (phone.call?.state === 'ended') phone.call = null;
  }, ENDED_VISIBLE);
};

const lookup = async number => {
  if (number.length < 8) return;
  try {
    const { data } = await VoiceAPI.lookup(number);
    if (phone.call?.number === number) phone.call.lookup = data;
  } catch {
    // sem nome do cliente a ligação continua normal
  }
};

const attach = (current, info) => {
  clearTimeout(endedTimer);
  session = current;
  phone.call = {
    ...info,
    muted: false,
    held: false,
    transferTo: '',
    answeredAt: null,
    endReason: '',
    lookup: null,
  };
  let iceTimer = null;
  current.on('icecandidate', ({ candidate, ready }) => {
    if (candidate.type === 'srflx') ready();
    else if (!iceTimer) iceTimer = setTimeout(ready, ICE_WAIT);
  });
  current.on('peerconnection', ({ peerconnection }) =>
    playRemote(peerconnection)
  );
  // quem liga ouve "chamando" enquanto o outro lado só avisa que está tocando (180); com o som da operadora
  // (183 com áudio), toca o som dela
  current.on('progress', ({ originator, response }) => {
    if (originator !== 'remote' || phone.call?.state !== 'dialing') return;
    if (response.body) stopTone();
    else if (response.status_code === 180) startTone('ringback');
  });
  current.on('accepted', () => {
    stopTone();
    phone.call.state = 'active';
    phone.call.answeredAt = Date.now();
  });
  current.on('ended', event => finish(current, endReason(event)));
  current.on('failed', event => finish(current, endReason(event)));
  lookup(info.number);
};

const onSession = ({ session: current, originator, request }) => {
  if (originator === 'local') {
    attach(current, { direction: 'outbound', number: dialing, name: '' });
    phone.call.state = 'dialing';
    playRemote(current.connection);
    return;
  }
  // já em ligação: a central toca para os outros
  if (session) {
    current.terminate({ status_code: 486 });
    return;
  }
  attach(current, {
    direction: 'inbound',
    number: request.from.uri.user || '',
    name: request.from.display_name || '',
  });
  phone.call.state = 'ringing';
  startTone('incoming');
};

const disconnect = () => {
  generation += 1;
  stopTone();
  if (session && !session.isEnded()) session.terminate();
  session = null;
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

// mode: try (só se nenhuma aba estiver com o telefone), wait (assume quando a outra aba fechar) ou steal
const requestLine = (key, mode) => {
  if (!navigator.locks) {
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
        phone.status = 'other_tab';
        requestLine(key, 'wait');
        return undefined;
      }
      held = true;
      waiting = null;
      connect();
      return new Promise(resolve => {
        releaseLock = resolve;
      });
    })
    .catch(() => {
      // outra aba trouxe o telefone para ela ("usar nesta aba")
      if (!held || accountKey !== key) return;
      disconnect();
      phone.status = 'other_tab';
      requestLine(key, 'wait');
    });
};

export const stopPhone = () => {
  accountKey = null;
  waiting?.abort();
  waiting = null;
  disconnect();
  phone.status = 'off';
};

export const startPhone = async accountId => {
  if (accountKey === accountId) return;
  stopPhone();
  accountKey = accountId;
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
  requestLine(accountId, 'try');
};

// de novo do zero (ramal ou senha podem ter mudado nas Configurações); nunca no meio de uma ligação
export const restartPhone = () => {
  if (phone.call && phone.call.state !== 'ended') return;
  const accountId = accountKey;
  stopPhone();
  startPhone(accountId);
};

export const useThisTab = () => {
  if (accountKey) requestLine(accountKey, 'steal');
};

// número de cliente (com ou sem +55, máscara, espaços) ou ramal; devolve o motivo quando não dá
export const dial = number => {
  const target = String(number || '').replace(/\D/g, '');
  if (phone.status === 'other_tab') return 'OTHER_TAB';
  if (phone.status !== 'ready') return 'NOT_READY';
  if (session) return 'IN_CALL';
  if (!target) return 'INVALID';
  dialing = target;
  ua.call(`sip:${target}@${config.domain}`, {
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
  });
  return null;
};

export const answer = () => {
  if (phone.call?.state !== 'ringing') return;
  stopTone();
  session.answer({
    mediaConstraints: MEDIA,
    pcConfig: { iceServers: ICE_SERVERS },
  });
};

// recusar só tira esta pessoa: a central segue tocando para os outros
export const hangup = () => {
  if (!session || session.isEnded()) return;
  session.terminate(
    phone.call.state === 'ringing' ? { status_code: 486 } : undefined
  );
};

export const toggleMute = () => {
  if (phone.call?.state !== 'active') return;
  if (phone.call.muted) session.unmute({ audio: true });
  else session.mute({ audio: true });
  phone.call.muted = !phone.call.muted;
};

export const sendDigit = digit => {
  if (phone.call?.state === 'active') {
    session.sendDTMF(digit, { transportType: 'RFC2833' });
  }
};

export const clearEndedCall = () => {
  if (phone.call?.state === 'ended') phone.call = null;
};

// espera: o outro lado fica em silêncio até voltar (Entrega 23)
export const toggleHold = () => {
  if (phone.call?.state !== 'active') return;
  if (phone.call.held) session.unhold();
  else session.hold();
  phone.call.held = !phone.call.held;
};

// transferência direta para outro ramal: a central liga para ele e, quando confirma, esta ligação acaba aqui
export const transfer = extension => {
  if (phone.call?.state !== 'active' || !/^\d{3}$/.test(extension)) return;
  phone.call.transferTo = extension;
  const current = session;
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
};

// áudio da ligação (o microfone da pessoa e o som do outro lado), para as barras que mexem com a voz
export const callStreams = () => {
  const track = session?.connection
    ?.getSenders()
    .find(sender => sender.track?.kind === 'audio')?.track;
  return {
    local: track ? new MediaStream([track]) : null,
    remote: remoteAudio.srcObject,
  };
};
