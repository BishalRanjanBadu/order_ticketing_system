/*
  Service Worker for Ticket Rail push notifications.

  This file must be served from the SAME directory as index.html (the site
  root), so its default scope covers the whole app. If you host index.html
  at e.g. https://you.github.io/order_ticketing_system/, this file needs to
  live at https://you.github.io/order_ticketing_system/sw.js — right next
  to it, not in a subfolder.

  This is the one piece of the app that keeps running in the background
  even when no tab is open — it's how a notification can appear on a
  lock screen or in the OS notification tray at all.
*/

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// A push message arrived from the browser's push service (sent by our
// Supabase Edge Function). Show it as a real OS notification.
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: 'Ticket Rail', body: event.data ? event.data.text() : '' }; }

  const title = data.title || 'Ticket Rail';
  const options = {
    body: data.body || '',
    icon: data.icon || undefined,
    badge: data.badge || undefined,
    tag: data.order_id || undefined,   // same order_id replaces, rather than stacking duplicates
    renotify: !!data.order_id,
    data: { order_id: data.order_id || null, url: data.url || './' },
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Person tapped the notification — focus an existing tab if one's open,
// otherwise open a new one, and jump straight to the relevant order.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const orderId = event.notification.data && event.notification.data.order_id;
  const baseUrl = (event.notification.data && event.notification.data.url) || './';
  const targetUrl = orderId ? `${baseUrl}?open_order=${orderId}` : baseUrl;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.postMessage({ type: 'open_order', order_id: orderId });
          return client.focus();
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});
