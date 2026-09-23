// 泗月 工作台 Service Worker — 离线缓存应用外壳
const CACHE = 'siyue-v36';
const SHELL = ['index.html','manifest.webmanifest','icon-192.png','icon-512.png','apple-touch-icon.png'];
const MD_DIR = /^\/(reports|summaries)\/.*\.md(\?.*)?$|^\/[a-z-]+-\d{4}-\d{2}-\d{2}\.html(\?.*)?$/;

self.addEventListener('install', e => {
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    // 逐个缓存，单个失败不影响整体安装（避免旧 SW 因某个资源 404 而永不升级）
    await Promise.allSettled(SHELL.map(u => c.add(u).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  const path = url.pathname;
  // 1) 报告/总结的 .md：NETWORK-ONLY —— 每次重新拉取，绝不缓存，绝不回退旧缓存
  //    （彻底绕开 CloudStudio 对不存在 .md 返回 HTML 兜底页造成的缓存污染）
  if (MD_DIR.test(path)) {
    e.respondWith(fetch(e.request).catch(() => new Response('', { status: 404, headers: { 'content-type': 'text/plain' } })));
    return;
  }
  // 1.5) 自动收藏数据 favorites.json：NETWORK-FIRST —— 每日更新，优先拉最新，失败回退缓存
  if (path === '/favorites.json') {
    e.respondWith(
      fetch(e.request).then(res => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, copy));
        }
        return res;
      }).catch(() => caches.match(e.request))
    );
    return;
  }
  // 1.6) 手动收藏持久化 manual_favorites.json：NETWORK-FIRST（同 favorites.json）
  if (path === '/manual_favorites.json') {
    e.respondWith(
      fetch(e.request).then(res => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, copy));
        }
        return res;
      }).catch(() => caches.match(e.request))
    );
    return;
  }
  const isNav = e.request.mode === 'navigate' || path.endsWith('/index.html') || path === '/' || path.endsWith('/');
  // 2) 导航/应用外壳：network-first
  if (isNav) {
    e.respondWith(
      fetch(e.request).then(res => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, copy));
        }
        return res;
      }).catch(() => caches.match(e.request).then(c => c || caches.match('index.html')))
    );
    return;
  }
  // 3) 其他静态资源：cache-first
  e.respondWith(
    caches.match(e.request).then(cached => {
      const net = fetch(e.request).then(res => {
        if (res && res.status === 200 && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, copy));
        }
        return res;
      }).catch(() => cached);
      return cached || net;
    })
  );
});
