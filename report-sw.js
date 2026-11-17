/* Report writer disabled — self-destruct: clear caches and unregister. */
self.addEventListener("install", e => { self.skipWaiting(); });
self.addEventListener("activate", e => {
  e.waitUntil((async () => {
    const ks = await caches.keys();
    await Promise.all(ks.map(k => caches.delete(k)));
    await self.registration.unregister();
    const cls = await self.clients.matchAll({ type: "window" });
    cls.forEach(c => c.navigate(c.url));
  })());
});
