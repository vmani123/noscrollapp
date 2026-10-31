/* Chrome-only companion. No URLs, titles, page contents, or history leave Chrome. */
(() => {
  'use strict';
  const host = 'com.intentional_browsing.guard';
  let port = null;
  let connecting = false;

  function connect() {
    if (port || connecting) return;
    connecting = true;
    try {
      const connection = chrome.runtime.connectNative(host);
      port = connection;
      connection.onMessage.addListener(async message => {
        if (message?.type !== 'challenge' || typeof message.nonce !== 'string') return;
        try {
          const manifest = chrome.runtime.getManifest();
          const [windows, siteAccess, incognito] = await Promise.all([
            chrome.windows.getAll({windowTypes: ['normal', 'popup']}),
            chrome.permissions.contains({origins: manifest.host_permissions,
              permissions: ['declarativeNetRequest']}),
            chrome.extension.isAllowedIncognitoAccess()
          ]);
          if (port !== connection) return;
          connection.postMessage({
            type: 'health', nonce: message.nonce, version: manifest.version,
            extensionID: chrome.runtime.id, windows: windows.length,
            siteAccess, incognito
          });
        } catch {
          // A failed permission/window query must not count as a healthy extension.
          try { connection.disconnect(); } catch { /* Already disconnected. */ }
          if (port === connection) port = null;
        }
      });
      connection.onDisconnect.addListener(() => {
        // Reading lastError prevents an unhandled error when the companion isn't installed.
        void chrome.runtime.lastError;
        if (port === connection) port = null;
        setTimeout(connect, 3000);
      });
    } catch {
      port = null;
      setTimeout(connect, 3000);
    } finally {
      connecting = false;
    }
  }
  chrome.runtime.onStartup.addListener(connect);
  chrome.runtime.onInstalled.addListener(connect);
  chrome.alarms.onAlarm.addListener(alarm => {
    if (alarm.name === 'guard-reconnect') connect();
  });
  chrome.alarms.create('guard-reconnect', {periodInMinutes: 0.5});
  connect();
})();
