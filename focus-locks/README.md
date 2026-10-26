# Intentional browsing and locked blocks

Status: the original 0.1.0 Chrome extension was observed installed and enabled on this Mac. The 0.2.0 update and [Mac Chrome guard](macos-guard/README.md) are installed and enforcing for Chrome. Both active Chrome profiles report healthy native connections and required permissions. Live observation tests verified the failure countdown, recovery, and automatic guard restart without closing the working browser; actual Chrome termination was not exercised. The iPhone prototype was development-signed and installed on VikPhone on October 15, 2026, without upgrading macOS or Xcode; authorization and enforcement remain untested. The 42 route cases pass, JavaScript syntax checks pass, and the Safari macOS app compiles with signing disabled. The feed-removal UI still needs a full live browser review. Existing Control Room files and existing Cold Turkey blocks were left intact. The Mac already has Cold Turkey Pro 4.9, but its interface showed **Fix extensions** during inspection.

## The Mac behavior

The extension allows YouTube searches and individual videos, plus individual Reddit posts and their comment trees. It blocks homepages, subreddit listings, channel listings, subscriptions, Shorts routes, and other feeds. It hides recommendations and Shorts shelves and switches off the YouTube player's autoplay toggle. Playlist URLs are reduced to the selected video. Reddit search runs through Google so the Reddit search page cannot become another feed.

This is a distinction between **individual pages and discovery feeds**. It cannot judge whether a specific video or post is educational. An entertaining video opened deliberately still works; a Short opened using a normal `/watch?v=…` link is also indistinguishable from another video by its URL. Website layout changes may require selector updates.

The extension reads/modifies YouTube, Reddit, and LinkedIn pages only. It has no analytics, stored browsing history, account, or general access to other websites. For LinkedIn it stores only the last count and zero-confirmation timestamp for each activity badge, plus the shared visit expiry in local extension storage; no notification text or messages are stored. The Chrome update communicates window counts and permission status to a local Mac guard, without sending URLs or page contents. The extension remains removable through browser settings. With the guard enabled, missing protection makes Chrome close after a grace period; the per-user guard itself is not a tamper-proof lock.

### LinkedIn activity gate (0.3.1)

The Chromium and Firefox packages include a notification gate. Visiting LinkedIn loads the site behind a shield while the extension reads the Notifications, Messaging, and Network items' English accessible labels. A positive count from any of these badges unlocks a single five-minute visit. The visit remains open if opening Notifications clears the badge, but it cannot be extended by refreshing, opening another tab, or restarting the background worker. After expiry, another visit needs an increased count in any individual badge or a confirmed zero followed by a positive count in that badge. Counts are tracked independently so a decrease in notifications cannot mask a new message or connection alert. A transient loading zero must be observed twice at least three seconds apart before it rearms the gate. Sign-in and account-checkpoint pages remain available so authentication is possible.

This uses LinkedIn's **new/unseen activity badges**, not verified read receipts for every item. Messaging's navigation badge counts unseen messages and can clear when Messaging opens even if conversations remain unread. Network includes connection requests and can also include other invitations; it is not a precise count of pending connection requests. A Network alert for an accepted connection can also appear in Notifications. The implementation reads badge numbers only and does not open conversations, accept connections, or store names/message text. An unchanged count cannot distinguish a new arrival offset by an old item being cleared, and a capped count can miss arrivals. Unrecognized or localized navigation layouts fail closed; LinkedIn UI changes may require an update. There is no polling of LinkedIn when no LinkedIn tab is open, no private API calls, and no automatic reading or marking of notifications. A valid visit permits normal LinkedIn navigation for its remaining time. The Safari wrapper has not yet been rebuilt with this gate.

Reload Intentional Browsing in **every installed Chrome profile**, approve LinkedIn site access if Chrome requests it, and refresh existing LinkedIn tabs. The companion guard update accepts 0.2.0, 0.3.0, and 0.3.1 during this transition; its permission check covers all host permissions requested by the loaded version. Tests: `node focus-locks/tests/linkedin.test.cjs` from the workspace root. Gate logic, separate message/network arrival detection, migration from bell-only storage, and background storage are tested; live activation awaits the user's extension reload because browser automation cannot access Chrome's internal Extensions page.

## Covering browsers

There is no universal browser extension installation. Install in **every browser and profile you use**, including private browsing where supported:

* Chrome, Brave, Edge, and compatible Chromium browsers: load `packages/chromium` from that browser's Extensions page in Developer mode. Keep that directory in place.
* Firefox: source is in `packages/firefox`. `about:debugging` can load it temporarily for testing; it disappears after a restart. A persistent Firefox release requires Mozilla signing. Do not count a temporary install as ongoing protection.
* Safari: the generated Xcode project is in `safari/Intentional Browsing`. The unsigned verification build is in `build/safari/Build/Products/Release/Intentional Browsing.app`. A local build needs appropriate signing and then enabling the extension in Safari Settings. No valid code-signing identity was found on this Mac. Unsigned development builds are not a permanent deployment; this kit does not weaken Safari's security settings.

Browsers without this extension remain unprotected. Cold Turkey can reinforce URL blocking across its supported browsers and attempt to block unsupported browsers. Its unsupported-browser detection is best effort, so a strict all-browser deployment needs an explicitly approved browser list and management of installation of other browsers and in-app web viewers.

For convenient everyday use, enable the feed extension in each browser. The [Mac guard](macos-guard/README.md) adds Chrome closure if the extension is missing, disabled, or missing required permissions. It does not cover other browsers or protect itself against deliberate local tampering. For stronger resistance, browser-managed deployment or a trusted administrator is needed. Cold Turkey requires its **own** extension; that requirement does not prevent removing this separate extension.

## Optional Cold Turkey layer

Cold Turkey understands URL patterns and exceptions, but not a user's purpose. Its [guide](https://getcoldturkey.com/support/user-guide/) documents import lists, URL wildcards, browser extensions, and timed locks.

Create a new `Intentional research` block. Import `cold-turkey/research-blocked.txt` into Websites and `research-exceptions.txt` into Website Exceptions. The separate feed-removal extension is still needed: exceptions allow individual videos, including videos reached through recommendations. Keep this block separate from existing blocks; another block can still deny an allowed page.

Create optional `Social` and `Extra` blocks from the corresponding lists. For the extra block, add no research exceptions.

Repair Cold Turkey's browser extensions before enabling blocks. Check protection in every browser/profile, including private windows. For locked sessions, use its Timer lock rather than a random-text unlock. Review unsupported-browser and extension-failure protection in its settings. The import lists have not been tested against the installed Cold Turkey version; use a short trial before a long lock.

## iPhone: what matches your requested modes

A new native app prototype is now included in [`ios/README.md`](ios/README.md). Its app and Screen Time extensions compile and its independent lock-window tests pass. It implements timed app/site blocking and requests uninstall protection, with **no in-app early exit**. It is development-signed and installed on VikPhone; launch, authorization, and enforcement still require testing. This is distinct from the third-party options below; the OS authorization boundary still applies.

| Request | Ordinary iPhone blocker |
| --- | --- |
| Block Instagram and TikTok apps and websites | Select apps and domains separately; verify all installed browsers. |
| Block Shorts while retaining the native YouTube app | No reliable guarantee from the normal Screen Time app-blocking API. |
| Extra mode: block all Reddit and YouTube | Select both apps and their web domains/short-link domains. |
| A one-week lock | AppBlock documents a week-long Strict Mode timer. |
| Cannot uninstall or turn off under any circumstances | Ordinary self-managed apps do not meet this absolute requirement. |

YouTube's built-in Shorts limit can be set to zero, but [Google says it can be ignored](https://support.google.com/youtube/answer/16671528). This is not a locked block.

### Closest app setup, with an explicit limitation

[AppBlock's iOS Strict Mode](https://appblock.app/help/apple/strict-mode/) supports a one-week Timer condition, locking schedules, disabling app deletion/installation, and preventing time changes. Create the app/domain selections first, ensure the blocking itself remains active for the full requested period, and then enable the Timer condition. Do not select PIN, charger, or cooldown unlocking. A lock on settings alone does not make a schedule run outside its selected hours.

However, [AppBlock documents an emergency unblocking flow](https://appblock.app/help/apple/troubleshoot/). That means it **does not satisfy your no-early-exit requirement**, even with uninstall protection enabled. Its guidance for iOS 26.4 and later also recommends a Screen Time passcode to protect permission removal, ideally held by another person.

For stronger practical protection, a trusted person should control the restriction passcode **and recovery**, not merely choose a code you can reset through your own Apple Account. [Apple describes Screen Time recovery](https://support.apple.com/102677). Do not misrepresent account eligibility to obtain parental authorization.

### The stronger design

A supervised iPhone with device management controlled by a trusted administrator or independent service can enforce app-removal and web restrictions outside the blocker's own UI. A timed-lock service would need to deny removal and policy weakening until an immutable expiry and restore access automatically afterward. That is a managed deployment, not something a normal App Store app can impose on its owner. Supervision is also not an absolute guarantee against device restoration; [Apple documents removing manual supervision by erasing](https://support.apple.com/guide/apple-configurator-mac/cadbf9b585/mac).

Apple's newer [system-wide URL filtering](https://support.apple.com/guide/deployment/filter-content-dep1129ff8d2/web) supports full URLs on iOS/macOS 26 and later under supervision. It is a possible component of a custom managed system, not proof that Shorts can be distinguished within native app traffic. Your Mac currently runs macOS 14.6.1.

Preserving useful YouTube on an iPhone is more practical by blocking its native app and using one controlled browser with feed removal, then restricting alternate browsers. That changes your “any browser” preference. Alternatively block all YouTube during phone locks and use the Mac for learning videos. Neither change has been chosen for you.

## Verification before relying on protection

The route tests exercise home/feed URLs, mobile and old Reddit URLs, direct posts/videos, share redirects, Shorts, searches, malformed inputs, and domain lookalikes:

```sh
node tests/policy.test.cjs
```

In each installed browser/profile, verify direct and internal navigation, Back/Forward, private windows, homepage, Shorts, search, direct video, autoplay, recommendations, Reddit thread comments, and subreddit feeds. Recheck after a restart. Native app blocking and website blocking on the phone must also be checked separately, including Wi-Fi and cellular. A successful unit test does not establish device enforcement.

Build the Safari wrapper for verification:

```sh
xcodebuild -project 'safari/Intentional Browsing/Intentional Browsing.xcodeproj' \
  -scheme 'Intentional Browsing' -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/safari \
  CODE_SIGNING_ALLOWED=NO build
```

That command verifies compilation only. For a normal Safari installation, configure a valid Apple signing team in Xcode and build with signing enabled. Firefox also needs a signed package for normal persistent installation. Chromium's local developer installation does not require signing, but needs explicit browser installation and site-access approval.
