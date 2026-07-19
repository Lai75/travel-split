'use strict';
// 缓存策略:先回缓存、后台更新(stale-while-revalidate)。新版本第二次打开生效。
// 只缓存本站文件和 jsdelivr 的 supabase-js;Supabase 数据请求一律直连网络。
const CACHE = 'travel-split-v1';
const cacheable = h => h === location.hostname || h === 'cdn.jsdelivr.net';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(clients.claim()));
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || !cacheable(url.hostname)) return;
  e.respondWith(caches.open(CACHE).then(async cache => {
    const hit = await cache.match(e.request);
    const net = fetch(e.request).then(r => {
      if (r.ok || r.type === 'opaque') cache.put(e.request, r.clone());
      return r;
    }).catch(() => hit);
    return hit || net;
  }));
});
