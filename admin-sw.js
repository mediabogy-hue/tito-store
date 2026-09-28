const CACHE='blnk-admin-v2-20260928';
self.addEventListener('install',e=>{self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil((async()=>{const ks=await caches.keys();await Promise.all(ks.filter(k=>k.startsWith('blnk-admin-')&&k!==CACHE).map(k=>caches.delete(k)));await self.clients.claim()})())});
self.addEventListener('fetch',e=>{if(e.request.method!=='GET')return;const u=new URL(e.request.url);if(/\/(operations|orders-admin|admin|customers-admin|balance-admin|suppliers-admin|supplier-finance|offers-admin|sales-dashboard|pos)\.html$/.test(u.pathname)||u.pathname.endsWith('/admin-theme.css')){e.respondWith(fetch(e.request,{cache:'no-store'}));return}e.respondWith(fetch(e.request).catch(()=>caches.match(e.request)))});
