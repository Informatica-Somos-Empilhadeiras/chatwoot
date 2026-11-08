/* eslint-disable no-restricted-globals */
/* globals clients */
// OUTSIDER: aviso novo (push) do Chatwoot. Carregado pelo public/sw.js (importScripts).
//   Foto de quem mandou, "Nome · de onde veio" e o texto. Várias mensagens da mesma conversa viram um aviso só
//   ("3 mensagens novas · texto"). Se a pessoa já está olhando aquela conversa, não mostra nada.
//   Botões: "Abrir conversa" (usa a aba do Chatwoot que já está aberta) e "Marcar como lida".
self.outsiderPush = (() => {
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

  const show = async data => {
    const open = await windows();
    const watching = open.some(
      client =>
        client.visibilityState === 'visible' &&
        client.focused &&
        samePath(client.url, data.path)
    );
    if (watching) return null;

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
    const actions = [{ action: 'open', title: data.open_label || 'Abrir' }];
    if (data.read) actions.push({ action: 'read', title: data.read_label });

    return self.registration.showNotification(data.title, {
      body,
      icon: data.icon,
      badge: data.badge,
      tag: data.tag,
      renotify: true,
      timestamp: Date.now(),
      actions,
      data: {
        outsider: 1,
        url: data.url,
        path: data.path,
        read: data.read,
        count: count > 0 ? next : 1,
      },
    });
  };

  const markRead = token =>
    fetch('/outsider/push/read', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token }),
      credentials: 'omit',
    }).catch(() => null);

  // abre na aba do Chatwoot que já está aberta (a tela troca sem recarregar); sem aba, abre uma nova
  const openConversation = async data => {
    const open = await windows();
    const app = open.find(client => {
      try {
        const url = new URL(client.url);
        return (
          url.origin === self.location.origin && url.pathname.startsWith('/app')
        );
      } catch (e) {
        return false;
      }
    });
    if (app) {
      // troca a tela primeiro; trazer a janela para frente pode ser recusado pelo navegador
      app.postMessage({ type: 'outsider:push-open', path: data.path });
      return app.focus().catch(() => null);
    }
    return clients.openWindow ? clients.openWindow(data.url) : null;
  };

  const click = event => {
    const { notification } = event;
    const data = notification.data || {};
    if (!data.outsider) return false;
    notification.close();
    const work =
      event.action === 'read' && data.read
        ? markRead(data.read)
        : openConversation(data);
    event.waitUntil(work);
    return true;
  };

  return { handles, show, click };
})();
