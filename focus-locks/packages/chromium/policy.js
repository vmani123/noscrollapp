(function (root) {
  'use strict';
  const videoID = /^[A-Za-z0-9_-]{11}$/;
  const hostIs = (host, domain) => host === domain || host.endsWith('.' + domain);

  function classify(raw) {
    let url;
    try { url = new URL(raw); } catch { return { site: null, allowed: false }; }
    const host = url.hostname.toLowerCase();
    const path = url.pathname;
    if (!['http:', 'https:'].includes(url.protocol)) return { site: null, allowed: false };
    if (host === 'youtu.be') {
      const id = path.slice(1);
      return { site: 'youtube', allowed: videoID.test(id), kind: 'redirect' };
    }
    if (hostIs(host, 'youtube.com') || hostIs(host, 'youtube-nocookie.com')) {
      const video = path === '/watch' && videoID.test(url.searchParams.get('v') || '');
      const search = path === '/results' && !!(url.searchParams.get('search_query') || '').trim();
      const embed = /^\/embed\/[A-Za-z0-9_-]{11}\/?$/.test(path);
      return { site: 'youtube', allowed: video || search || embed,
        kind: video || embed ? 'video' : search ? 'search' : 'feed' };
    }
    if (host === 'redd.it') {
      return { site: 'reddit', allowed: /^\/[a-z0-9]+\/?$/i.test(path), kind: 'redirect' };
    }
    if (hostIs(host, 'reddit.com')) {
      const thread = /^\/(?:r\/[a-z0-9_]+\/)?comments\/[a-z0-9]+(?:\/|$)/i.test(path);
      // New Reddit share URLs resolve to individual posts, but /s/ itself isn't a feed.
      const share = /^\/r\/[a-z0-9_]+\/s\/[a-z0-9]+\/?$/i.test(path);
      return { site: 'reddit', allowed: thread || share, kind: thread ? 'thread' : share ? 'redirect' : 'feed' };
    }
    return { site: null, allowed: true, kind: 'other' };
  }

  const api = Object.freeze({ classify });
  root.IntentionalPolicy = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(globalThis);
