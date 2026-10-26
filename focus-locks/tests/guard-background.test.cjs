const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function event() {
  let fn;
  return {addListener: listener => { fn = listener; }, fire: value => fn?.(value)};
}
async function run() {
  let connections = 0;
  let siteAccess = true;
  let incognito = true;
  let failQuery = false;
  const sent = [];
  let port;
  const timers = [];
  const chrome = {
    runtime: {
      id: 'test-extension', lastError: null,
      getManifest: () => ({version: '0.2.0', host_permissions: ['*://*.youtube.com/*']}),
      connectNative: name => {
        assert.equal(name, 'com.intentional_browsing.guard'); connections++;
        port = {onMessage: event(), onDisconnect: event(),
          postMessage: value => sent.push(value), disconnect: () => port.onDisconnect.fire()};
        return port;
      }, onStartup: event(), onInstalled: event()
    },
    windows: {getAll: async () => {
      if (failQuery) throw Error('Window query failed');
      // Intentionally include private windows; no URLs or titles should be reported.
      return [{id: 1, incognito: false}, {id: 2, incognito: true}];
    }},
    permissions: {contains: async () => siteAccess},
    extension: {isAllowedIncognitoAccess: async () => incognito},
    alarms: {create: () => {}, onAlarm: event()}
  };
  vm.runInNewContext(fs.readFileSync('focus-locks/extension/guard-background.js', 'utf8'),
    {chrome, setTimeout: fn => timers.push(fn)});
  assert.equal(connections, 1);
  await port.onMessage.fire({type: 'challenge', nonce: 'a'});
  assert.deepEqual(JSON.parse(JSON.stringify(sent[0])), {
    type: 'health', nonce: 'a', version: '0.2.0', extensionID: 'test-extension',
    windows: 2, siteAccess: true, incognito: true
  });
  siteAccess = false; incognito = false;
  await port.onMessage.fire({type: 'challenge', nonce: 'b'});
  assert.equal(sent[1].siteAccess, false);
  assert.equal(sent[1].incognito, false);
  await port.onMessage.fire({type: 'anything', nonce: 'ignored'});
  assert.equal(sent.length, 2);
  failQuery = true;
  await port.onMessage.fire({type: 'challenge', nonce: 'c'});
  assert.equal(sent.length, 2, 'API errors must never produce a healthy report');
  assert.equal(timers.length, 1);
  timers.pop()();
  assert.equal(connections, 2, 'reconnect after a failed host or permission query');
  chrome.runtime.onStartup.fire();
  assert.equal(connections, 2, 'startup must not duplicate an active host');
  console.log('Guard worker protocol, permissions, private-window count, and reconnect checks passed.');
}
run().catch(error => { console.error(error); process.exit(1); });
