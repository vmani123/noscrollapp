const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const policy = require('../extension/policy.js');

// Exercise the content script's playback and SPA decisions without site/network access.
let time = 10000;
const handlers = {};
const videoHandlers = {};
const attributes = {};
let pauses = 0;
let inspect;
const video = {
  autoplay: true,
  removeAttribute(name) { assert.equal(name, 'autoplay'); },
  pause() { pauses++; },
  addEventListener(name, fn) { videoHandlers[name] = fn; }
};
function element() {
  return {style: {}, setAttribute() {}, addEventListener() {},
    append(...children) { children.forEach(child => { child.isConnected = true; }); }};
}
const root = element();
root.setAttribute = (key, value) => { attributes[key] = value; };
const location = {href: 'https://www.bilibili.com/video/BV1B7411m7LV/'};
const document = {
  documentElement: root,
  createElement: element,
  querySelectorAll: selector => selector === 'video' ? [video] : [],
  addEventListener(name, fn) { handlers[name] = fn; }
};
vm.runInNewContext(fs.readFileSync('focus-locks/extension/content.js', 'utf8'), {
  IntentionalPolicy: policy, URL, location, document,
  Date: {now: () => time},
  window: {addEventListener() {}},
  MutationObserver: class { observe() {} },
  setInterval(fn) { inspect = fn; },
  requestAnimationFrame(fn) { fn(); }
});
assert.equal(attributes['data-intentional-allowed'], 'true');
assert.equal(attributes['data-intentional-site'], 'bilibili');
assert.equal(video.autoplay, false);
handlers.play();
assert.equal(pauses, 1, 'unsolicited initial playback is paused');
handlers.pointerdown({isTrusted: true});
videoHandlers.play();
assert.equal(pauses, 1, 'explicit play gesture is allowed');
videoHandlers.ended();
assert.equal(pauses, 2, 'ending a requested video pauses playback');
time += 2000;
videoHandlers.play();
assert.equal(pauses, 3, 'automatic replay after completion is paused');
location.href = 'https://www.bilibili.com/video/BV1Q541167Qg/';
inspect();
assert.equal(attributes['data-intentional-allowed'], 'false', 'automatic SPA next video is shielded');
assert.equal(pauses, 4);
console.log('Bilibili initial autoplay, explicit play, ending, replay, and automatic navigation checks passed.');
