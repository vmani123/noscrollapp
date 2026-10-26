(() => {
  'use strict';
  if (!LinkedInGatePolicy.isLinkedIn(location.href)) return;
  const api = globalThis.browser || globalThis.chrome;
  let shield, description, status, countdown;
  let busy = false, scheduled = false;
  let expiresAt = 0;
  let latestCount = null;
  const started = Date.now();

  function setText(element, value) {
    if (element.textContent !== value) element.textContent = value;
  }

  function ui() {
    if (!shield) {
      shield = document.createElement('div');
      shield.id = 'intentional-linkedin-gate';
      shield.setAttribute('role', 'region');
      shield.setAttribute('aria-label', 'LinkedIn notification gate');
      const box = document.createElement('section');
      const title = document.createElement('h1');
      title.textContent = 'LinkedIn opens for new activity.';
      description = document.createElement('p');
      const note = document.createElement('p');
      note.textContent = 'A new notification, message, or Network alert unlocks one five-minute visit. Refreshing does not extend it.';
      const retry = document.createElement('button');
      retry.textContent = 'Check again';
      retry.addEventListener('click', () => location.reload());
      const signIn = document.createElement('a');
      signIn.href = 'https://www.linkedin.com/login';
      signIn.textContent = 'Sign in';
      box.append(title, description, note, retry, signIn);
      shield.append(box);
      status = document.createElement('div');
      status.id = 'intentional-linkedin-status';
      countdown = document.createElement('span');
      const notifications = document.createElement('a');
      notifications.href = 'https://www.linkedin.com/notifications/';
      notifications.textContent = 'View notifications';
      status.append(countdown, notifications);
      for (const [text, path] of [['Messages', 'messaging/'], ['Connections', 'mynetwork/']]) {
        const link = document.createElement('a');
        link.href = 'https://www.linkedin.com/' + path;
        link.textContent = text;
        status.append(link);
      }
    }
    for (const node of [shield, status]) if (!node.isConnected) document.documentElement.append(node);
  }

  function render(error) {
    ui();
    const signingIn = LinkedInGatePolicy.isSignIn(location.href);
    const allowed = signingIn || expiresAt > Date.now();
    const value = String(allowed);
    if (document.documentElement.getAttribute('data-intentional-linkedin-allowed') !== value) {
      document.documentElement.setAttribute('data-intentional-linkedin-allowed', value);
    }
    shield.hidden = allowed;
    status.hidden = !allowed || signingIn;
    if (allowed && !signingIn) {
      const seconds = Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000));
      setText(countdown, `Activity visit · ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')} left`);
    } else if (!allowed) {
      const text = error || (latestCount === 0 ? 'No new notifications, messages, or Network alerts are waiting.'
        : latestCount > 0 ? 'These activity counts have already unlocked a visit. Come back when new activity arrives.'
        : Date.now() - started < 12000 ? 'Checking notifications, messages, and Network alerts…'
        : 'LinkedIn activity could not be verified. Sign in if needed, then check again.');
      setText(description, text);
      document.querySelectorAll('video, audio').forEach(media => media.pause());
    }
  }

  function readActivity() {
    const links = [];
    for (const link of document.querySelectorAll('a[href]')) {
      let url;
      try { url = new URL(link.getAttribute('href'), location.href); } catch { continue; }
      if (!LinkedInGatePolicy.sourceForUrl(url.href) ||
          link.closest('#intentional-linkedin-status, #intentional-linkedin-gate')) continue;
      links.push({href: url.href, label: link.getAttribute('aria-label'),
        fragments: Array.from(link.querySelectorAll('span')).map(span => span.textContent)});
    }
    return LinkedInGatePolicy.readBadges(links);
  }

  async function inspect() {
    scheduled = false;
    render();
    if (busy || LinkedInGatePolicy.isSignIn(location.href)) return;
    busy = true;
    const counts = readActivity();
    const known = Object.values(counts).filter(value => value !== null);
    latestCount = known.length ? known.reduce((a, b) => a + b, 0) : null;
    try {
      const response = await api.runtime.sendMessage({type: 'linkedin-gate-check', counts});
      expiresAt = response?.allowed && Number.isFinite(response.expiresAt) ? response.expiresAt : 0;
      render(response?.error);
    } catch {
      expiresAt = 0;
      render('The extension was updated or could not verify access. Refresh this page.');
    } finally { busy = false; }
  }

  function schedule() {
    if (!scheduled) { scheduled = true; setTimeout(inspect, 250); }
  }
  new MutationObserver(schedule).observe(document.documentElement,
    {childList: true, subtree: true, attributes: true, attributeFilter: ['aria-label']});
  for (const type of ['pageshow', 'popstate']) window.addEventListener(type, inspect);
  document.addEventListener('visibilitychange', inspect);
  document.addEventListener('play', event => {
    if (!LinkedInGatePolicy.isSignIn(location.href) && expiresAt <= Date.now()) event.target.pause?.();
  }, true);
  setInterval(inspect, 1000);
  inspect();
})();
