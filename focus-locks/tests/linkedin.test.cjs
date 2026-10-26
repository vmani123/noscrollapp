const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const policy = require('../extension/linkedin-policy.js');

assert.equal(policy.badgeCount('Notifications, 24 new notifications'), 24);
assert.equal(policy.badgeCount('Notifications, 0 new notifications'), 0);
assert.equal(policy.badgeCount('Notifications, 1 unread notification'), 1);
assert.equal(policy.badgeCount('Notifications', ['99+', 'Notifications']), 99);
assert.equal(policy.badgeCount('Notifications'), 0);
assert.equal(policy.badgeCount('Messaging, 24 new notifications'), null);
assert.equal(policy.badgeCount('Unknown navigation label'), null);
assert.equal(policy.badgeCount('Messaging, 3 new notifications', [], 'messages'), 3);
assert.equal(policy.badgeCount('Messaging, 1 unread message', [], 'messages'), 1);
assert.equal(policy.badgeCount('Network, 2 new notifications', [], 'connections'), 2);
assert.equal(policy.badgeCount('My Network, 4 pending invitations', [], 'connections'), 4);
assert.equal(policy.badgeCount('Messaging', ['9+', 'Messaging'], 'messages'), 9);
assert.equal(policy.badgeCount('Network, 2 new notifications', [], 'messages'), null);
assert.deepEqual(policy.readBadges([
  {href:'https://www.linkedin.com/notifications/',label:'Notifications, 5 new notifications'},
  {href:'https://www.linkedin.com/messaging/',label:'Messaging, 2 new notifications'},
  {href:'https://www.linkedin.com/mynetwork',label:'Network, 1 new notifications'},
  {href:'https://www.linkedin.com/feed/',label:'Home, 99 new notifications'},
  {href:'https://linkedin.com.example.org/messaging/',label:'Messaging, 99 new notifications'}
]), {notifications:5,messages:2,connections:1});
assert.equal(policy.isLinkedIn('https://linkedin.com.example.org/'), false);
assert.equal(policy.isLinkedIn('https://www.linkedin.com/feed/'), true);
assert.equal(policy.isSignIn('https://www.linkedin.com/checkpoint/challenge/abc'), true);
assert.equal(policy.isSignIn('https://www.linkedin.com/login-success/feed/'), false);
assert.equal(policy.isSignIn('https://www.linkedin.com/feed/'), false);

const start = 1000000;
let result = policy.check(null, null, start);
assert.equal(result.allowed, false, 'Unknown badge fails closed');
result = policy.check(result.state, 0, start);
assert.equal(result.allowed, false, 'Zero notifications cannot unlock');
result = policy.check(result.state, 24, start);
assert.equal(result.allowed, true);
const expiry = start + policy.visitLength;
assert.equal(result.expiresAt, expiry);
result = policy.check(result.state, 24, start + 2000);
assert.equal(result.expiresAt, expiry, 'Reloading cannot extend the visit');
result = policy.check(result.state, 0, start + 3000);
assert.equal(result.allowed, true, 'Opening Notifications may clear the badge without ending the visit');
result = policy.check(result.state, null, start + 4000);
assert.equal(result.allowed, true, 'Navigation without a bell preserves only the existing visit');
result = policy.check(result.state, 0, expiry);
assert.equal(result.allowed, false, 'Expiry is exclusive and survives zero-badge checks');
result = policy.check(result.state, 1, expiry + 1);
assert.equal(result.allowed, true, 'A new notification after zero unlocks a new visit');
result = policy.check(result.state, 2, expiry + 2);
assert.equal(result.expiresAt, expiry + 1 + policy.visitLength, 'Arrivals during a visit do not extend it');
result = policy.check(result.state, 2, expiry + 1 + policy.visitLength);
assert.equal(result.allowed, false, 'An unchanged unread badge cannot repeatedly unlock visits');
result = policy.check(result.state, 3, expiry + 2 + policy.visitLength);
assert.equal(result.allowed, true, 'An increased bell count is a new notification signal');
assert.equal(policy.check({schema:1, lastCount:24, expiresAt:expiry}, 24, start - 1).allowed,
  false, 'Moving the clock backward cannot extend a stored visit beyond five minutes');
let stale = policy.check({schema:1, lastCount:24, expiresAt:0}, 0, start);
stale = policy.check(stale.state, 24, start + 1000);
assert.equal(stale.allowed, false, 'A transient loading zero cannot rearm a consumed badge');
stale = policy.check(stale.state, 0, start + 2000);
stale = policy.check(stale.state, 0, start + 5000);
assert.equal(policy.check(stale.state, 1, start + 6000).allowed, true,
  'A confirmed zero followed by a new notification rearms the gate');

const empty = {notifications:0,messages:0,connections:0};
const baseline = policy.check(null, empty, start).state;
for (const source of ['messages', 'connections']) {
  const opened = policy.check(baseline, {...empty,[source]:1}, start + 1);
  assert.equal(opened.allowed,true, `${source} alone unlocks the gate`);
  assert.equal(policy.check(opened.state, {...empty,[source]:1},opened.expiresAt).allowed,false,
    `An unchanged ${source} badge cannot reopen a visit`);
}
let swapped = policy.check(null, {notifications:5,messages:0,connections:0}, start);
swapped = policy.check(swapped.state, {notifications:4,messages:1,connections:0}, swapped.expiresAt);
assert.equal(swapped.allowed,true,'A new message unlocks even when the overall total stays five');
let falling = policy.check(null, {notifications:5,messages:0,connections:0}, start);
falling = policy.check(falling.state, {notifications:0,messages:0,connections:1}, falling.expiresAt);
assert.equal(falling.allowed,true,'A connection alert unlocks even when the overall total falls');
const legacy = {schema:1,lastCount:5,expiresAt:start+10000,zeroSince:0};
const upgraded = policy.check(legacy,{notifications:5,messages:0,connections:0},start);
assert.equal(upgraded.expiresAt,legacy.expiresAt,'Upgrading does not extend the old visit');
assert.equal(policy.check({...legacy,expiresAt:0},{notifications:5},start).allowed,false,
  'Upgrading does not reuse the consumed notification badge');
const missing = policy.check(swapped.state,{notifications:null,messages:null,connections:null},swapped.expiresAt);
assert.equal(missing.allowed,false,'Missing all navigation badges cannot unlock access');
assert.equal(missing.state.channels.messages.lastCount,1,'Missing badges preserve the known per-channel baseline');

async function backgroundChecks() {
  const saved = {};
  let listener, failWrite = false, now = start;
  const api = {
    runtime: {onMessage: {addListener(fn) { listener = fn; }}},
    storage: {local: {
      async get(key) { return {[key]: saved[key]}; },
      async set(value) { if (failWrite) throw Error('Disk unavailable'); Object.assign(saved, value); }
    }}
  };
  function boot() {
    vm.runInNewContext(fs.readFileSync('focus-locks/extension/linkedin-background.js', 'utf8'),
      {chrome:api, LinkedInGatePolicy:policy, Date:{now:()=>now}});
  }
  function check(count, url = 'https://www.linkedin.com/feed/') {
    return new Promise(resolve => {
      const message = {type:'linkedin-gate-check', ...(typeof count === 'object' && count !== null ? {counts:count} : {count})};
      const handled = listener(message, {url}, resolve);
      if (handled !== true) resolve(null);
    });
  }
  boot();
  assert.equal(await check(100, 'https://example.org/'), null, 'Other sites cannot grant visits');
  const [first, second] = await Promise.all([check(24), check(24)]);
  assert.equal(first.expiresAt, second.expiresAt, 'Concurrent tabs share one visit');
  now += 5000;
  boot();
  assert.equal((await check(24)).expiresAt, first.expiresAt, 'Worker restart preserves the original expiry');
  now = first.expiresAt;
  assert.equal((await check(24)).allowed, false, 'Reload or restart after expiry cannot reuse the old badge');
  failWrite = true;
  assert.equal((await check(25)).allowed, false, 'A visit cannot open before persistence succeeds');
  failWrite = false;
  const messageVisit = await check({notifications:24,messages:1,connections:0});
  assert.equal(messageVisit.allowed,true,'Background accepts the separate-count protocol');
  assert.equal(messageVisit.counts.messages,1);
  assert.equal(messageVisit.count,25);
  now+=1000;
  assert.equal((await check({notifications:24,messages:1,connections:1})).expiresAt,messageVisit.expiresAt,
    'A connection arrival during a message visit cannot extend it');
  console.log('LinkedIn notification/message/network badges, independent arrivals, migration, expiry, reload, concurrent tabs, worker restart, and failure checks passed.');
}
backgroundChecks().catch(error => {console.error(error); process.exit(1);});
