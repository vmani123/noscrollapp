(() => {
  'use strict';
  let shield;
  let queued = false;
  const videoTargets = new WeakSet();
  const finishedVideos = new WeakSet();
  let recentGesture = 0;
  let selectedVideo = videoKey(location.href);
  let requestedVideo = null;
  const initial = IntentionalPolicy.classify(location.href);
  if (!initial.site) return;

  function videoKey(raw) {
    const policy = IntentionalPolicy.classify(raw);
    if (!['youtube', 'bilibili'].includes(policy.site) || policy.kind !== 'video') return null;
    const url = new URL(raw);
    if (policy.site === 'bilibili') {
      return 'bilibili:' + (url.pathname.startsWith('/video/') ? url.pathname.split('/')[2]
        : url.searchParams.get('bvid') || url.searchParams.get('aid')) + ':' + (url.searchParams.get('p') || '1');
    }
    return url.pathname === '/watch' ? url.searchParams.get('v') : url.pathname.split('/')[2];
  }

  function showShield(policy) {
    if (!shield) {
      shield = document.createElement('div');
      shield.id = 'intentional-browsing-shield';
      shield.setAttribute('role', 'region');
      shield.setAttribute('aria-label', 'Feed blocked');
      const box = document.createElement('section');
      box.style.cssText = 'max-width:520px;width:100%';
      const title = document.createElement('h1');
      title.textContent = policy.site === 'instagram' ? 'Instagram is blocked.'
        : policy.site === 'threads' ? 'Threads is blocked.' : 'Open something on purpose.';
      const description = document.createElement('p');
      description.textContent = policy.site === 'youtube'
        ? 'YouTube feeds and Shorts are blocked. Search for a topic or open a specific video.'
        : policy.site === 'instagram' ? 'Instagram is always blocked in this browser.'
        : policy.site === 'threads' ? 'Threads is fully blocked in this browser.'
        : policy.site === 'bilibili' ? 'Bilibili feeds are blocked. Search for a topic or open a specific video.'
        : 'Reddit feeds are blocked. Open a specific post from your search results.';
      box.append(title, description);
      if (!['threads', 'instagram'].includes(policy.site)) {
        const form = document.createElement('form');
        const input = document.createElement('input');
        input.required = true;
        input.type = 'search';
        input.placeholder = policy.site === 'youtube' ? 'What do you want to learn?'
          : policy.site === 'bilibili' ? 'Search Bilibili videos' : 'Search Reddit posts';
        input.setAttribute('aria-label', input.placeholder);
        input.style.cssText = 'width:100%;box-sizing:border-box;padding:12px;border-radius:8px;font:inherit';
        const button = document.createElement('button');
        button.type = 'submit';
        button.textContent = 'Search';
        button.style.cssText = 'margin-top:12px;padding:10px 18px;border-radius:8px;font:inherit;cursor:pointer';
        form.append(input, button);
        form.addEventListener('submit', event => {
          event.preventDefault();
          const query = input.value.trim();
          if (!query) return;
          const target = policy.site === 'youtube'
            ? 'https://www.youtube.com/results?search_query=' + encodeURIComponent(query)
            : policy.site === 'bilibili' ? 'https://search.bilibili.com/all?keyword=' + encodeURIComponent(query)
            : 'https://www.google.com/search?q=' + encodeURIComponent('site:reddit.com/r/ ' + query);
          location.assign(target);
        });
        box.append(form);
      }
      shield.append(box);
    }
    if (!shield.isConnected) document.documentElement.append(shield);
    shield.hidden = false;
  }

  function trimDiscovery() {
    // Catch recommendations in newer layouts whose element names change.
    document.querySelectorAll('a[href]').forEach(link => {
      let target;
      try { target = new URL(link.getAttribute('href'), location.href); } catch { return; }
      const policy = IntentionalPolicy.classify(target.href);
      if (policy.site && !policy.allowed) {
        link.style.setProperty('display', 'none', 'important');
      }
      if (initial.site === 'reddit' && policy.site === 'reddit' && policy.kind === 'thread') {
        const current = location.pathname.match(/\/comments\/([a-z0-9]+)/i)?.[1];
        const next = target.pathname.match(/\/comments\/([a-z0-9]+)/i)?.[1];
        if (current && next && current.toLowerCase() !== next.toLowerCase()) {
          link.style.setProperty('display', 'none', 'important');
        }
      }
    });
  }

  function protectPlayback(policy) {
    document.querySelectorAll('video').forEach(video => {
      if (!policy.allowed) { video.pause(); return; }
      video.autoplay = false;
      video.removeAttribute('autoplay');
      if (!videoTargets.has(video)) {
        videoTargets.add(video);
        video.addEventListener('ended', () => {
          if (['youtube', 'bilibili'].includes(initial.site)) {
            finishedVideos.add(video);
            video.pause();
          }
        });
        video.addEventListener('play', () => {
          if (initial.site === 'bilibili' && Date.now() - recentGesture > 1500) video.pause();
          if (initial.site === 'youtube' && finishedVideos.has(video)) {
            if (Date.now() - recentGesture > 1500) video.pause();
            else finishedVideos.delete(video);
          }
        });
      }
    });
    if (policy.site === 'youtube' && policy.kind === 'video') {
      const toggle = document.querySelector('.ytp-autonav-toggle-button[aria-checked="true"]');
      if (toggle) toggle.click();
      // Remove explicit playlist context so playing a requested video won't chain a playlist.
      const url = new URL(location.href);
      if ((url.pathname === '/watch' || url.pathname.startsWith('/embed/')) &&
          ['list', 'index', 'playlist'].some(key => url.searchParams.has(key))) {
        url.searchParams.delete('list');
        url.searchParams.delete('index');
        url.searchParams.delete('playlist');
        location.replace(url.href);
      }
    }
    if (policy.site === 'bilibili' && policy.kind === 'video') {
      const url = new URL(location.href);
      if (url.hostname === 'player.bilibili.com' && url.searchParams.get('autoplay') !== '0') {
        url.searchParams.set('autoplay', '0');
        location.replace(url.href);
      }
    }
  }

  function inspect() {
    queued = false;
    let policy = IntentionalPolicy.classify(location.href);
    const currentVideo = videoKey(location.href);
    if (currentVideo && selectedVideo && currentVideo !== selectedVideo && currentVideo !== requestedVideo) {
      // A same-page automatic transition must not select another video for you.
      policy = { ...policy, allowed: false, kind: 'automatic' };
    } else if (policy.allowed) {
      selectedVideo = currentVideo;
      if (currentVideo === requestedVideo) requestedVideo = null;
    }
    document.documentElement.setAttribute('data-intentional-allowed', String(policy.allowed));
    document.documentElement.setAttribute('data-intentional-blocked', String(!policy.allowed));
    document.documentElement.setAttribute('data-intentional-site', policy.site || '');
    document.documentElement.setAttribute('data-intentional-kind', policy.kind || '');
    if (!policy.allowed) showShield(policy);
    else if (shield) shield.hidden = true;
    protectPlayback(policy);
    trimDiscovery();
  }

  function schedule() {
    if (!queued) { queued = true; requestAnimationFrame(inspect); }
  }
  // Cancel known feed destinations before a site's SPA router sees the click.
  document.addEventListener('click', event => {
    const link = event.composedPath().find(node => node instanceof HTMLAnchorElement);
    if (!link) return;
    const target = IntentionalPolicy.classify(link.href);
    if (target.site && !target.allowed) {
      event.preventDefault();
      event.stopImmediatePropagation();
    } else if (event.isTrusted && !event.ctrlKey && !event.metaKey && !event.shiftKey &&
               (!link.target || link.target === '_self')) {
      requestedVideo = videoKey(link.href);
    }
  }, true);
  for (const type of ['pointerdown', 'keydown']) document.addEventListener(type, event => {
    if (event.isTrusted) recentGesture = Date.now();
  }, true);
  document.addEventListener('play', () => {
    const policy = IntentionalPolicy.classify(location.href);
    if (!policy.allowed) protectPlayback(policy);
    if (initial.site === 'bilibili' && Date.now() - recentGesture > 1500) {
      document.querySelectorAll('video').forEach(video => video.pause());
    }
  }, true);
  new MutationObserver(schedule).observe(document.documentElement, {childList: true, subtree: true});
  document.addEventListener('yt-navigate-finish', inspect);
  window.addEventListener('popstate', event => {
    if (event.isTrusted) requestedVideo = videoKey(location.href);
    inspect();
  });
  window.addEventListener('pageshow', inspect);
  document.addEventListener('visibilitychange', inspect);
  setInterval(inspect, 750);
  inspect();
})();
