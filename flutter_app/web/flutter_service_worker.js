const RESET_VERSION = 'admin-transfer-ui-bbc0d01';

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
    await self.clients.claim();

    const clients = await self.clients.matchAll({
      includeUncontrolled: true,
      type: 'window',
    });
    await Promise.all(clients.map((client) => {
      const url = new URL(client.url);
      if (url.searchParams.get('__sw_reset') === RESET_VERSION) {
        return client.navigate(client.url);
      }
      url.searchParams.set('__sw_reset', RESET_VERSION);
      return client.navigate(url.toString());
    }));

    await self.registration.unregister();
  })());
});

self.addEventListener('fetch', () => {});
