// OUTSIDER: este navegador e o push novo. Pede a licença do navegador (só ao clicar em "Ativar"), assina o push com a
// chave do Chatwoot e guarda o aparelho com um nome ("Chrome · Windows"). O estado que as telas mostram fica em pushState.
import { reactive } from 'vue';
import OutsiderPushAPI from 'dashboard/api/outsider/push';

export const pushState = reactive({
  loaded: false,
  info: null,
  permission: 'default',
  supported: false,
  endpoint: null,
});

const urlKey = base64 => {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4);
  const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from([...raw].map(char => char.charCodeAt(0)));
};

const keyText = buffer =>
  btoa(String.fromCharCode.apply(null, new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

export const isSupported = () =>
  'serviceWorker' in navigator &&
  'PushManager' in window &&
  'Notification' in window;

// iPhone e iPad só recebem push com o Chatwoot na Tela de Início (regra da Apple)
export const isAppleMobile = () =>
  /iPhone|iPad|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

export const deviceLabel = () => {
  const ua = navigator.userAgent;
  let browser = 'Navegador';
  if (/Edg\//.test(ua)) browser = 'Edge';
  else if (/OPR\//.test(ua)) browser = 'Opera';
  else if (/Firefox\//.test(ua)) browser = 'Firefox';
  else if (/Chrome\//.test(ua)) browser = 'Chrome';
  else if (/Safari\//.test(ua)) browser = 'Safari';
  let system = '';
  if (/Android/.test(ua)) system = 'Android';
  else if (isAppleMobile()) system = 'iPhone';
  else if (/Windows/.test(ua)) system = 'Windows';
  else if (/Mac OS X/.test(ua)) system = 'Mac';
  else if (/Linux/.test(ua)) system = 'Linux';
  return system ? `${browser} · ${system}` : browser;
};

// updateViaCache 'none': o navegador sempre confere o sw.js e o outsider-push-sw.js no servidor (sem cache),
// então a versão nova do aviso chega no próximo carregamento do Chatwoot
const registration = async () => {
  const registered = await navigator.serviceWorker.register('/sw.js', {
    updateViaCache: 'none',
  });
  registered.update().catch(() => {});
  return navigator.serviceWorker.ready;
};

const saveDevice = async subscription => {
  const { data } = await OutsiderPushAPI.register({
    endpoint: subscription.endpoint,
    p256dh: keyText(subscription.getKey('p256dh')),
    auth: keyText(subscription.getKey('auth')),
    label: deviceLabel(),
  });
  pushState.info = data;
  pushState.endpoint = subscription.endpoint;
  return data;
};

const subscribe = async () => {
  const ready = await registration();
  const existing = await ready.pushManager.getSubscription();
  if (existing) return existing;
  return ready.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlKey(window.chatwootConfig.vapidPublicKey),
  });
};

export const loadPush = async () => {
  pushState.supported = isSupported();
  pushState.permission = pushState.supported
    ? Notification.permission
    : 'unsupported';
  try {
    const { data } = await OutsiderPushAPI.get();
    pushState.info = data;
  } finally {
    pushState.loaded = true;
  }
  return pushState.info;
};

// ao abrir o Chatwoot: com licença dada, garante que este aparelho está guardado (uma vez por sessão)
export const syncDevice = async () => {
  if (!pushState.supported || !window.chatwootConfig?.vapidPublicKey) return;
  if (Notification.permission === 'denied') {
    if (pushState.info?.permission !== 'denied')
      OutsiderPushAPI.permission('denied').catch(() => {});
    return;
  }
  if (Notification.permission !== 'granted') return;
  const subscription = await subscribe();
  pushState.endpoint = subscription.endpoint;
  const tail = subscription.endpoint.slice(-24);
  const known = (pushState.info?.devices || []).some(
    device => device.tail === tail
  );
  let done = false;
  try {
    done = sessionStorage.getItem('outsider_push_synced') === tail;
  } catch {
    done = false;
  }
  if (known && done) return;
  await saveDevice(subscription);
  try {
    sessionStorage.setItem('outsider_push_synced', tail);
  } catch {
    // sem sessionStorage só repete na próxima vez
  }
};

// botão "Ativar": a licença do navegador só pode ser pedida depois de um clique
export const activatePush = async () => {
  const permission = await Notification.requestPermission();
  pushState.permission = permission;
  if (permission !== 'granted') {
    OutsiderPushAPI.permission(permission).catch(() => {});
    return false;
  }
  const subscription = await subscribe();
  await saveDevice(subscription);
  return true;
};

export const isThisDevice = device =>
  !!pushState.endpoint && pushState.endpoint.slice(-24) === device.tail;
