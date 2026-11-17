/* AFD Report Writer — app-shell cache, SCOPED to report files only.
   Fix for the stuck-TV bug: the previous version intercepted EVERY GET
   request in its scope (including Supabase /rest/v1 data calls from
   index.html), served them cache-first, and never expired them — so a
   browser that had ever opened report.html could serve the dashboard a
   frozen copy of the call list forever. This version only handles the
   report app shell; all other requests go straight to the network. */
const CACHE = "afd-reports-v2";
const SHELL = ["report.html", "report-manifest.json", "report-icon.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(
    ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const url = new URL(e.request.url);
  // Only same-origin report-shell files are ours to cache. Everything
  // else — Supabase data, Maps, hydrants.json, index.html — bypasses.
  const isShell = url.origin === self.location.origin &&
    SHELL.some(f => url.pathname.endsWith("/" + f) || url.pathname.endsWith(f));
  if (!isShell) return; // let the browser fetch normally
  e.respondWith(
    caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match("report.html")))
  );
});
