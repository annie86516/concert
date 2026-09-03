const CACHE_NAME = "trio-ticket-v3";
const APP_FILES = ["./", "./index.html", "./manifest.webmanifest", "./icons/icon-192.png", "./icons/icon-512.png"];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_FILES)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", event => {
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith(fetch(event.request).then(response => {
    const copy = response.clone();
    caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
    return response;
  }).catch(() => caches.match(event.request).then(response => response || caches.match("./index.html"))));
});

self.addEventListener("push", event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = {body: event.data ? event.data.text() : ""}; }
  event.waitUntil(self.registration.showNotification(data.title || "搶票提醒", {
    body: data.body || "搶票時間即將到",
    icon: "icons/icon-192.png",
    badge: "icons/icon-192.png",
    tag: data.tag || "ticket-reminder",
    requireInteraction: data.requireInteraction !== false,
    data: {url: data.url || "./"}
  }));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const target = event.notification.data && event.notification.data.url || "./";
  event.waitUntil(clients.matchAll({type: "window", includeUncontrolled: true}).then(windows => {
    const appWindow = windows.find(client => new URL(client.url).origin === self.location.origin);
    if (appWindow) { appWindow.focus(); if (/^https?:\/\//i.test(target)) return clients.openWindow(target); return appWindow; }
    return clients.openWindow(target);
  }));
});
