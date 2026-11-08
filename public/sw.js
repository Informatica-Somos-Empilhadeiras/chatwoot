/* eslint-disable no-restricted-globals, no-console */
/* globals clients */
// OUTSIDER: aviso novo (foto, "Nome · origem", texto, agrupado por conversa). Ver public/outsider-push-sw.js
importScripts('/outsider-push-sw.js');

self.addEventListener('push', event => {
  let notification = event.data && event.data.json();
  // OUTSIDER: aviso novo
  if (self.outsiderPush && self.outsiderPush.handles(notification)) {
    event.waitUntil(self.outsiderPush.show(notification));
    return;
  }

  event.waitUntil(
    self.registration.showNotification(notification.title, {
      tag: notification.tag,
      data: {
        url: notification.url,
      },
    })
  );
});

self.addEventListener('notificationclick', event => {
  // OUTSIDER: aviso novo (Abrir conversa / Marcar como lida)
  if (self.outsiderPush && self.outsiderPush.click(event)) return;
  let notification = event.notification;

  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(windowClients => {
      let matchingWindowClients = windowClients.filter(
        client => client.url === notification.data.url
      );

      if (matchingWindowClients.length) {
        let firstWindow = matchingWindowClients[0];
        if (firstWindow && 'focus' in firstWindow) {
          firstWindow.focus();
          return;
        }
      }
      if (clients.openWindow) {
        clients.openWindow(notification.data.url);
      }
    })
  );
});
