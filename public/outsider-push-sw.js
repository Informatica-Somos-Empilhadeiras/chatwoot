/* eslint-disable no-restricted-globals */
/* globals clients */
// OUTSIDER: aviso novo (push) do Chatwoot. Carregado pelo public/sw.js (importScripts).
//   No visual do Teams: foto redonda de quem mandou (sem foto, as iniciais numa cor) com o símbolo do canal no canto,
//   "Nome · de onde veio" e o texto. Várias mensagens da mesma conversa viram um aviso só ("3 mensagens novas · texto").
//   Se a pessoa já está olhando aquela conversa, não mostra nada.
//   Botões: "Envie uma resposta rápida" (escreve a resposta no próprio aviso, onde o navegador deixa) e
//   "Marcar como lida"; clicar no aviso abre a conversa na aba do Chatwoot que já está aberta.
//   Telefone: ligação tocando com o Chatwoot em segundo plano (a página pede o aviso, botões Atender e Recusar) e
//   "Ligação perdida" (push, botão "Ligar de volta").
// versão nova do aviso assume na hora (sem esperar a pessoa fechar todas as abas do Chatwoot)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(clients.claim()));

self.outsiderPush = (() => {
  const CALL_TAG = 'outsider-call';
  const COLORS = [
    '#0f766e',
    '#7c3aed',
    '#c2410c',
    '#1d4ed8',
    '#be185d',
    '#15803d',
    '#b45309',
    '#4338ca',
  ];
  const handles = data => !!(data && data.outsider);

  const samePath = (clientUrl, path) => {
    try {
      return new URL(clientUrl).pathname === path;
    } catch (e) {
      return false;
    }
  };

  const windows = () =>
    clients.matchAll({ type: 'window', includeUncontrolled: true });

  const appWindows = async () =>
    (await windows()).filter(client => {
      try {
        const url = new URL(client.url);
        return (
          url.origin === self.location.origin && url.pathname.startsWith('/app')
        );
      } catch (e) {
        return false;
      }
    });

  // --- foto redonda com o símbolo do canal no canto (desenhada aqui, vira o ícone do aviso) ---

  const bitmaps = new Map();
  const bitmap = async url => {
    if (!url) return null;
    if (bitmaps.has(url)) return bitmaps.get(url);
    try {
      const response = await fetch(url, { credentials: 'omit' });
      if (!response.ok) return null;
      const image = await createImageBitmap(await response.blob());
      // guarda só os símbolos dos canais (as fotos mudam)
      if (url.includes('/outsider/push/')) bitmaps.set(url, image);
      return image;
    } catch (e) {
      return null;
    }
  };

  const initials = name =>
    (name || '?')
      .replace(/[^\p{L}\p{N} ]/gu, ' ')
      .trim()
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map(word => word[0].toUpperCase())
      .join('') || '?';

  const colorOf = name => {
    let hash = 0;
    [...(name || '')].forEach(char => {
      hash = (hash * 31 + char.codePointAt(0)) % 100003;
    });
    return COLORS[hash % COLORS.length];
  };

  const toDataUrl = async canvas => {
    const blob = await canvas.convertToBlob({ type: 'image/png' });
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return `data:image/png;base64,${btoa(binary)}`;
  };

  const SIZE = 192;
  const avatar = async data => {
    if (typeof OffscreenCanvas === 'undefined') return null;
    try {
      const canvas = new OffscreenCanvas(SIZE, SIZE);
      const ctx = canvas.getContext('2d');
      const [photo, channel] = await Promise.all([
        bitmap(data.photo),
        bitmap(data.icon),
      ]);
      const center = SIZE / 2;
      ctx.save();
      ctx.beginPath();
      ctx.arc(center, center, center, 0, Math.PI * 2);
      ctx.clip();
      if (photo) {
        // preenche o círculo sem esticar a foto
        const scale = Math.max(SIZE / photo.width, SIZE / photo.height);
        const width = photo.width * scale;
        const height = photo.height * scale;
        ctx.drawImage(
          photo,
          (SIZE - width) / 2,
          (SIZE - height) / 2,
          width,
          height
        );
      } else {
        const name = data.person || data.title;
        ctx.fillStyle = colorOf(name);
        ctx.fillRect(0, 0, SIZE, SIZE);
        ctx.fillStyle = '#ffffff';
        ctx.font = '600 72px "Segoe UI", system-ui, -apple-system, sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(initials(name), center, center + 4);
      }
      ctx.restore();
      if (channel) {
        // símbolo do canal no canto, com uma borda branca (como a bolinha de status do Teams)
        const radius = 34;
        const x = SIZE - radius - 2;
        const y = SIZE - radius - 2;
        ctx.save();
        ctx.globalCompositeOperation = 'destination-out';
        ctx.beginPath();
        ctx.arc(x, y, radius + 6, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
        ctx.drawImage(channel, x - radius, y - radius, radius * 2, radius * 2);
      }
      return await toDataUrl(canvas);
    } catch (e) {
      return null;
    }
  };

  // --- push que chega do servidor ---

  const actionsFor = data => {
    if (data.call_label && data.number) {
      return [
        { action: 'dial', title: data.call_label },
        { action: 'open', title: data.open_label || 'Abrir' },
      ];
    }
    const actions = [];
    if (data.reply) {
      actions.push({
        action: 'reply',
        type: 'text',
        title: data.reply_label || 'Responder',
        placeholder: data.reply_placeholder || '',
      });
    } else {
      actions.push({ action: 'open', title: data.open_label || 'Abrir' });
    }
    if (data.read) actions.push({ action: 'read', title: data.read_label });
    return actions;
  };

  const show = async data => {
    const open = await windows();
    const watching = open.some(
      client =>
        client.visibilityState === 'visible' &&
        client.focused &&
        samePath(client.url, data.path)
    );
    // o push de teste aparece mesmo com a pessoa olhando a tela de onde mandou
    if (watching && !data.test) return null;

    const previous = await self.registration.getNotifications({
      tag: data.tag,
    });
    const count = previous.reduce(
      (total, item) => Math.max(total, (item.data && item.data.count) || 1),
      0
    );
    const next = count + 1;
    const body =
      count > 0
        ? `${(data.more || '%<n>s').replace('%<n>s', next)} · ${data.body}`
        : data.body;
    const icon = (await avatar(data)) || data.photo || data.icon;

    return self.registration.showNotification(data.title, {
      body,
      icon,
      badge: data.badge,
      tag: data.tag,
      renotify: true,
      timestamp: Date.now(),
      actions: actionsFor(data),
      data: {
        outsider: 1,
        url: data.url,
        path: data.path,
        read: data.read,
        reply: data.reply,
        number: data.number,
        title: data.title,
        icon,
        badge: data.badge,
        count: count > 0 ? next : 1,
      },
    });
  };

  const post = (path, payload) =>
    fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      credentials: 'omit',
    });

  const markRead = token =>
    post('/outsider/push/read', { token }).catch(() => null);

  // abre na aba do Chatwoot que já está aberta (a tela troca sem recarregar); sem aba, abre uma nova
  const isPhoneWindow = client =>
    new URL(client.url).pathname.includes('/telefone');

  const openConversation = async (data, extra = {}) => {
    // a janela própria do telefone não troca de tela: usa uma aba do Chatwoot
    const app = (await appWindows()).find(client => !isPhoneWindow(client));
    if (app) {
      // troca a tela primeiro; trazer a janela para frente pode ser recusado pelo navegador
      app.postMessage({
        type: 'outsider:push-open',
        path: data.path,
        ...extra,
      });
      return app.focus().catch(() => null);
    }
    if (!clients.openWindow) return null;
    const url = new URL(data.url);
    if (extra.dial) url.searchParams.set('outsider_dial', extra.dial);
    return clients.openWindow(url.toString());
  };

  // resposta rápida: manda e troca o aviso por "Você: ..." por alguns segundos (no celular o aviso para de girar)
  const quickReply = async (notification, data, text) => {
    let ok = false;
    try {
      ok = (await post('/outsider/push/reply', { token: data.reply, text })).ok;
    } catch (e) {
      ok = false;
    }
    const tag = notification.tag || 'outsider-reply';
    await self.registration.showNotification(data.title, {
      body: ok
        ? `Você: ${text}`
        : 'Não deu para enviar a resposta. Toque para abrir a conversa.',
      icon: data.icon,
      badge: data.badge,
      tag,
      silent: true,
      data: { ...data, count: 0, reply: ok ? null : data.reply },
    });
    if (!ok) return;
    await new Promise(resolve => {
      setTimeout(resolve, 4000);
    });
    const shown = await self.registration.getNotifications({ tag });
    shown.forEach(item => {
      if (item.data && item.data.count === 0) item.close();
    });
  };

  // --- ligação tocando (a página do Chatwoot pede o aviso; só aparece se nenhuma aba está na frente) ---

  const ring = async call => {
    const open = await appWindows();
    if (open.some(client => client.focused)) return null;
    const icon =
      (await avatar({
        person: call.person,
        title: call.title,
        photo: call.photo,
        icon: '/outsider/push/phone.png',
      })) || '/outsider/push/phone.png';
    return self.registration.showNotification(call.title, {
      body: call.body || '',
      icon,
      badge: '/outsider/push/phone-badge.png',
      tag: CALL_TAG,
      // a foto e o nome chegam depois: troca o aviso sem tocar de novo
      renotify: false,
      requireInteraction: true,
      actions: [
        { action: 'answer', title: call.answer_label || 'Atender' },
        { action: 'decline', title: call.decline_label || 'Recusar' },
      ],
      data: { outsider: 1, call: 'ring' },
    });
  };

  const stopRinging = async () => {
    const shown = await self.registration.getNotifications({ tag: CALL_TAG });
    shown.forEach(item => item.close());
  };

  // a janela própria do telefone, se aberta; senão a aba da frente ou a primeira do Chatwoot
  const phoneWindow = async () => {
    const open = await appWindows();
    return (
      open.find(isPhoneWindow) || open.find(client => client.focused) || open[0]
    );
  };

  const callClick = async action => {
    const target = await phoneWindow();
    if (!target) return null;
    target.postMessage({ type: 'outsider:call', action: action || 'show' });
    if (action === 'decline') return null;
    return target.focus().catch(() => null);
  };

  const message = event => {
    const data = event.data || {};
    if (data.type === 'outsider:call-ring') {
      event.waitUntil(ring(data));
      return true;
    }
    if (data.type === 'outsider:call-stop') {
      event.waitUntil(stopRinging());
      return true;
    }
    return false;
  };

  const click = event => {
    const { notification } = event;
    const data = notification.data || {};
    if (!data.outsider) return false;
    notification.close();
    let work;
    if (data.call === 'ring') work = callClick(event.action);
    else if (event.action === 'read' && data.read) work = markRead(data.read);
    else if (event.action === 'reply' && data.reply && event.reply)
      work = quickReply(notification, data, event.reply);
    else if (event.action === 'dial' && data.number)
      work = openConversation(data, { dial: data.number });
    else work = openConversation(data);
    event.waitUntil(work);
    return true;
  };

  return { handles, show, click, message, avatar };
})();

self.addEventListener('message', event => {
  self.outsiderPush.message(event);
});
