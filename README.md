# NoScroll

Tools for deliberate browsing on a Mac and timed app/website blocking on an iPhone.

The project source and configurations are in [`focus-locks/`](focus-locks/). These are local prototypes: working blocking behavior has been reported on the iPhone, but unattended expiry, restarts, long blocks, and coverage across browsers still need verification. The Mac guard is a per-user companion, not an owner-proof security boundary.

## What's included

| Component | Source / configuration | Purpose |
| --- | --- | --- |
| Browser extension | [`extension`](focus-locks/extension/) | Allow YouTube searches/videos and individual Reddit threads; block feeds, Shorts routes, recommendations, and autoplay. |
| Chromium package | [`packages/chromium`](focus-locks/packages/chromium/) | Load unpacked in Chrome, Edge, Brave, and compatible browsers. |
| Firefox package | [`packages/firefox`](focus-locks/packages/firefox/) | Equivalent browser package; persistent installation requires Firefox signing. |
| LinkedIn gate | [`linkedin-policy.js`](focus-locks/extension/linkedin-policy.js) | New notification, Messaging, or Network badge activity unlocks one shared five-minute visit. |
| Safari wrapper | [`safari`](focus-locks/safari/) | Xcode macOS app and Safari web-extension project; additional signing and update work is required for current LinkedIn support. |
| Mac guard | [`macos-guard`](focus-locks/macos-guard/) | Detect missing/disabled Chrome protection and close Chrome after a grace period. |
| iPhone app | [`ios`](focus-locks/ios/) | Core/Extra selections and committed timed blocks up to seven days. Includes Device Activity monitor, shield UI, and shield action extensions. |
| Cold Turkey configuration | [`cold-turkey`](focus-locks/cold-turkey/) | Optional import lists and exceptions for a separate blocking layer. |

## Set up the browser extension

1. Clone this repository and keep it in a stable location.
2. In your Chromium browser, open the Extensions page, enable Developer mode, and choose **Load unpacked**.
3. Select `focus-locks/packages/chromium`.
4. Allow the requested YouTube, Reddit, and LinkedIn site access. Install in every browser profile you use, including private browsing where supported.
5. For the optional Chrome guard, follow [`macos-guard/README.md`](focus-locks/macos-guard/README.md). The guard's build derives its extension ID from the local package path, so rebuild/reinstall it if you move the checkout.

LinkedIn checks the site's English navigation badges when a LinkedIn tab is open. It tracks Notifications, Messaging, and Network separately; Network can include invitations beyond connection requests. Badge changes are a heuristic, not item-by-item read receipts. A visit expires after five minutes and is not extended by refreshing or opening more tabs.

Rebuild the checked-in browser packages and ZIPs after editing extension source:

```sh
python3 focus-locks/build-packages.py
```

Reload the extension manually in each browser/profile afterward. Safari's generated wrapper needs its own resource/configuration updates; the packaging script currently produces Chromium and Firefox packages.

## Set up the iPhone app

Open `focus-locks/ios/LockedBlocks.xcodeproj` in Xcode and select your Apple Developer Program signing team for the app and all three extensions. Family Controls development profiles, a registered device, the matching App Group, and on-device authorization are required. The existing team setting identifies the original development configuration; it does not include certificates, private keys, or provisioning profiles.

See [`ios/README.md`](focus-locks/ios/README.md) for signing, the successful signed-IPA USB installation route, and physical-device checks. `project.yml` is included for regeneration with XcodeGen. App and group identifiers must stay consistent across all targets and the shared store.

Individual Screen Time authorization remains revocable through iOS settings. The app has no in-app early-cancel feature and requests app-removal protection while a block is active, but it cannot guarantee an irreversible lock. Shorts-only filtering inside the native YouTube app is not implemented. Test short blocks and automatic restoration before relying on a week-long block.

## Verification

Run these from the repository root:

```sh
node focus-locks/tests/policy.test.cjs
node focus-locks/tests/guard-background.test.cjs
node focus-locks/tests/linkedin.test.cjs

xcrun swiftc -module-cache-path /private/tmp/noscroll-swift-cache \
  focus-locks/macos-guard/GuardCore.swift focus-locks/macos-guard/tests/main.swift \
  -o /private/tmp/noscroll-guard-tests
/private/tmp/noscroll-guard-tests

xcrun swiftc -module-cache-path /private/tmp/noscroll-swift-cache \
  focus-locks/ios/Shared/LockWindow.swift focus-locks/ios/Tests/main.swift \
  -o /private/tmp/noscroll-window-tests
/private/tmp/noscroll-window-tests
```

The Swift checks require a Mac with Xcode command-line tools. They verify state/timing logic, not enforcement by iOS or browser rendering. See the component READMEs for build and integration-test instructions.

## Local-only files

Build outputs, signed phone installation packages, provisioning profiles, signing keys, device-specific Xcode user state, and the unrelated personal dashboard are excluded from Git. Browser packages are included so a clone can be loaded directly.
