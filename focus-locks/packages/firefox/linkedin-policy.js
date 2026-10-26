(function (root) {
  'use strict';
  const visitLength = 5 * 60 * 1000;
  const sources = ['notifications', 'messages', 'connections'];
  const labels = {
    notifications: /^notifications\b/i,
    messages: /^messaging\b/i,
    connections: /^(?:my\s+)?network\b/i
  };

  function isLinkedIn(raw) {
    try {
      const url = new URL(raw);
      return ['https:', 'http:'].includes(url.protocol) &&
        (url.hostname === 'linkedin.com' || url.hostname.endsWith('.linkedin.com'));
    } catch { return false; }
  }

  function isSignIn(raw) {
    if (!isLinkedIn(raw)) return false;
    const path = new URL(raw).pathname;
    return /^\/(?:login|uas\/login|checkpoint|authwall|oauth)(?:\/|$)/.test(path);
  }

  // Use each navigation item's label, never the page title's combined counter.
  function badgeCount(label, fragments = [], source = 'notifications') {
    if (!labels[source]?.test(String(label || '').trim())) return null;
    const explicit = String(label || '').match(/(?:^|[,\s])(\d[\d,]*)(\+?)\s+(?:(?:new|unread|unseen|pending)\s+)?(?:notifications?|messages?|invitations?|connection\s+requests?)\b/i);
    if (explicit) return Number(explicit[1].replaceAll(',', ''));
    for (const fragment of fragments) {
      const numeric = String(fragment).trim().match(/^(\d[\d,]*)(?:\+)?$/);
      if (numeric) return Number(numeric[1].replaceAll(',', ''));
    }
    return /^(?:notifications|messaging|(?:my\s+)?network)\s*$/i.test(String(label).trim()) ? 0 : null;
  }

  function sourceForUrl(raw) {
    if (!isLinkedIn(raw)) return null;
    const path = new URL(raw).pathname.replace(/\/$/, '');
    return path === '/notifications' ? 'notifications' : path === '/messaging' ? 'messages'
      : path === '/mynetwork' ? 'connections' : null;
  }

  function readBadges(links) {
    const counts = {notifications: null, messages: null, connections: null};
    for (const link of links) {
      const source = sourceForUrl(link.href);
      if (!source || counts[source] !== null) continue;
      counts[source] = badgeCount(link.label, link.fragments, source);
    }
    return counts;
  }

  function check(previous, input, now) {
    const prior = previous && [1, 2].includes(previous.schema) ? previous : {};
    // Accept old tabs' bell-only checks and preserve their saved visit during upgrades.
    const incoming = input && typeof input === 'object' ? input : {notifications: input};
    const counts = {}, channels = {};
    let fresh = false;
    for (const source of sources) {
      const old = prior.schema === 1 && source === 'notifications' ? prior : prior.channels?.[source] || {};
      const lastCount = Number.isSafeInteger(old.lastCount) && old.lastCount >= 0 ? old.lastCount : null;
      const count = incoming[source];
      const known = Number.isSafeInteger(count) && count >= 0;
      counts[source] = known ? count : null;
      if (known && count > 0 && (lastCount === null || count > lastCount)) fresh = true;
      // Ignore a transient zero while LinkedIn is still loading account data.
      let zeroSince = Number.isFinite(old.zeroSince) && old.zeroSince > 0 && old.zeroSince <= now
        ? old.zeroSince : 0;
      let nextCount = known ? count : lastCount;
      if (known && count === 0 && lastCount > 0) {
        if (!zeroSince) zeroSince = now;
        if (now - zeroSince < 3000) nextCount = lastCount;
      } else if (known && count > 0) zeroSince = 0;
      channels[source] = {lastCount: nextCount, zeroSince};
    }
    let expiresAt = Number.isFinite(prior.expiresAt) && prior.expiresAt > now &&
      prior.expiresAt <= now + visitLength ? prior.expiresAt : 0;
    // An existing visit never extends, even when more notifications arrive.
    if (!expiresAt && fresh) expiresAt = now + visitLength;
    const state = {schema: 2, channels, expiresAt};
    const knownCounts = Object.values(counts).filter(value => value !== null);
    return {state, allowed: expiresAt > now, expiresAt, counts,
      count: knownCounts.length ? knownCounts.reduce((a, b) => a + b, 0) : null};
  }

  const api = Object.freeze({visitLength, isLinkedIn, isSignIn, badgeCount, sourceForUrl, readBadges, check});
  root.LinkedInGatePolicy = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(globalThis);
