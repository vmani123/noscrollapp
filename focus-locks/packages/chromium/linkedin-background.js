(() => {
  'use strict';
  const api = globalThis.browser || globalThis.chrome;
  const key = 'linkedin-notification-gate-v1';
  let queue = Promise.resolve();
  api.runtime.onMessage.addListener((message, sender, respond) => {
    if (message?.type !== 'linkedin-gate-check' || !LinkedInGatePolicy.isLinkedIn(sender.url)) return;
    const counts = message.counts ?? message.count;
    queue = queue.catch(() => {}).then(async () => {
      try {
        const saved = await api.storage.local.get(key);
        const result = LinkedInGatePolicy.check(saved[key], counts, Date.now());
        // Persist before opening the gate; reloads and other tabs share the same expiry.
        await api.storage.local.set({[key]: result.state});
        respond({allowed: result.allowed, expiresAt: result.expiresAt, count: result.count, counts: result.counts});
      } catch {
        respond({allowed: false, expiresAt: 0, error: 'Unable to verify the notification visit.'});
      }
    });
    return true;
  });
})();
