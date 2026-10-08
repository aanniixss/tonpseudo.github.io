// Service worker de BAKOU.
// Objectif : l'app s'installe sur le telephone et s'ouvre meme sans reseau.
// Regle d'or : on ne met JAMAIS l'API Supabase en cache. Un trade affiche
// doit toujours venir de la base, sinon on afficherait de fausses donnees.
const VERSION = 'bakou-v1';
const COQUILLE = [
  './app.html',
  './index.html',
  './manifest.webmanifest',
  './assets/icon-192.png',
  './assets/icon-512.png',
  './assets/icon-maskable-192.png',
  './assets/icon-maskable-512.png'
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(VERSION)
      // addAll echoue en bloc si un seul fichier manque : on les prend un par un
      .then(c => Promise.all(COQUILLE.map(u => c.add(u).catch(() => {}))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', e => {
  if (e.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  let u;
  try { u = new URL(req.url); } catch (_) { return; }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return;

  // Les donnees : toujours le reseau, jamais le cache.
  if (/supabase\.(co|in)$/.test(u.hostname) || u.pathname.indexOf('/rest/v1/') === 0
      || u.pathname.indexOf('/auth/v1/') === 0 || u.pathname.indexOf('/functions/v1/') === 0) return;

  const estPage = req.mode === 'navigate' || /\.html?$/.test(u.pathname);

  if (estPage) {
    // Reseau d'abord : une nouvelle version du site arrive tout de suite.
    e.respondWith(
      fetch(req).then(r => {
        if (r && r.ok) { const copie = r.clone(); caches.open(VERSION).then(c => c.put(req, copie)); }
        return r;
      }).catch(() => caches.match(req).then(r => r || caches.match('./app.html')))
    );
    return;
  }

  // Le reste (icones, polices, librairies CDN) : cache d'abord, c'est fige.
  e.respondWith(
    caches.match(req).then(enCache => {
      if (enCache) return enCache;
      return fetch(req).then(r => {
        if (r && (r.ok || r.type === 'opaque')) { const copie = r.clone(); caches.open(VERSION).then(c => c.put(req, copie)); }
        return r;
      });
    })
  );
});
