# Chrome extension guard for macOS

**Perry branch:** Chrome also blocks Threads completely. Grant Threads and Bilibili site access and the network-blocking permission when loading extension 0.3.2. See [Perry setup](../../PERRY-SETUP.md) for installation on another Mac. The status below describes the original development Mac.

This is an independent implementation of the browser-closing behavior requested. It does not use Cold Turkey's code or change Cold Turkey's configuration.

Status on this Mac: **installed and enforcing**, with healthy extension connections in both active Chrome profiles. The `IB` menu-bar item shows current protection status.

## Behavior

The native Mac app starts at login and launchd restarts it if it exits. Every 60 seconds it checks Google Chrome (and once immediately at launch). A native-messaging connection in each Chrome profile responds to random challenges every 60 seconds. A report expires after 75 seconds, and reports from dead native hosts or another Chrome process are rejected.

The guard requires the extension's requested site access (YouTube/Reddit, plus LinkedIn in 0.3.0) and **Allow in Incognito**. It requires a separate healthy native connection for each profile listed in Chrome's current `last_active_profiles` state, then checks that reported window coverage is at least the number of visible browsing-size Chrome windows. This avoids counting hidden tooltips/autocomplete windows or falsely rejecting minimized/other-space windows. The profile check still covers those hidden browsing windows. One profile with several windows cannot substitute for a missing profile connection. This is a conservative check for ordinary Chrome using its default data directory; guest windows, app windows, developer tools, custom data directories, and future Chrome state-format changes need separate validation. It is not a cryptographic mapping of each OS window to a profile.

When Chrome starts, it has **60 seconds** to become healthy. Once healthy, a problem has **10 seconds** to recover. Grace periods are evaluated on the 60-second check schedule, so closure happens at the next scheduled check after a grace deadline, rather than exactly 10 seconds after detection. The guard requests a normal Chrome exit, then forces termination on the following check if Chrome refuses. This affects **all windows in that Chrome process**, and unsaved browser work can be lost. Reopening Chrome provides a new 60-second repair interval. This deliberate setup allowance is also a potential bypass through repeated relaunches.

The guard displays a Mac window explaining the failure and an `IB` menu-bar status item. The status menu has no pause or quit action. Closing the explanation window does not stop enforcement. The app's observation mode never closes Chrome.

## Install

The double-click setup helpers are **Test Chrome Guard.command** (observation mode) and **Enable Chrome Guard.command** (enforcement after healthy status). They run the same steps below.

1. Run `python3 focus-locks/build-packages.py` from the repository root.
2. In **each Chrome profile you use**, go to `chrome://extensions`, enable Developer mode, and Load unpacked → `focus-locks/packages/chromium`. If it is already installed from that folder, click Reload instead. Approve any additional permission Chrome requests.
3. Open the extension's Details. Enable **Allow in Incognito** and allow access to all requested YouTube, Reddit, and LinkedIn sites. Refresh any YouTube/Reddit tabs already open when updating the extension.
4. Test with `python3 focus-locks/macos-guard/install.py --observe`. This builds the app, registers its native host, and starts its login agent without closing Chrome. Reload the extension after installing the native host, or wait for its reconnect alarm.
5. Check `~/Applications/Intentional Browsing Guard.app/Contents/MacOS/BrowserGuard --status` (quote the path in Terminal). It must report `observing: true` with no problem. Test all profiles, minimized windows, private windows, and popups you normally use.
6. Enable closing behavior with `python3 focus-locks/macos-guard/install.py`. The installer refuses to enable closure if its recent observation status shows a problem. Save browser work first. `IB` → Extension protection status shows the current state. Disable the extension to verify the warning and closure, then reopen Chrome and re-enable it during the repair interval.

The installer only changes this guard's own app, launch agent, and native-host registration. It does not close Chrome during installation, edit browser policies or profiles, or change another blocker's settings. Enforcement begins when the installed agent runs without `--observe`.

The extension ID is derived from the exact unpacked package directory. Keep that folder in place. Rebuild/reinstall the guard if the repository is moved; an extension loaded from another directory won't match the registered native host. The installed app is locally ad-hoc signed, not notarized or an App Store release.

## Scope and limits

**This is a per-user Chrome guard, not a tamper-proof timed lock.** A user who deliberately removes its login agent or edits its files can defeat it; the installer includes `--uninstall` for removal. Launchd restart handles ordinary process exits, not every deliberate attack. It does not implement Cold Turkey's protected uninstaller, installer blocking, time-change blocking, or Activity Monitor blocking. The local heartbeat files are not an administrator security boundary. The native host is restricted to this extension ID and accepts no web/HTTP connections, but a local user can modify/spoof user-owned files or invoke modified software.

Safari, Firefox, Edge, Brave, and in-app browsers are **not enforced by this Chrome guard**. Their existing feed-removal packages remain separate. Device management and an independently controlled administrator account are needed for substantially stronger protection against intentional tampering and alternate browsers.

No browsing URLs, titles, page contents, or history are sent to the guard. Reports contain only process/session identifiers, window counts, version, permission flags, and monotonic timestamps. Nothing is uploaded.

## Verification

```sh
node focus-locks/tests/policy.test.cjs
node focus-locks/tests/guard-background.test.cjs
xcrun swiftc -module-cache-path /private/tmp/intentional-swift-cache \
  focus-locks/macos-guard/GuardCore.swift focus-locks/macos-guard/tests/main.swift \
  -o /private/tmp/intentional-guard-tests
/private/tmp/intentional-guard-tests
python3 focus-locks/macos-guard/build.py
```

The 31 policy checks cover missing/expired/wrong-process reports, dead hosts, permission loss, old versions, extra visible windows, multiple profiles, duplicate reports, unreadable profile state, minimized/other-space windows, grace deadlines, and recovery. The worker protocol also has a mock integration test. On this Mac the updated extension connected from both active Chrome profiles with all required permissions. Before changing the polling interval to 60 seconds, a live observation-mode test paused a real native host, verified missing protection through its closure deadline while Chrome stayed open, and verified recovery. Launchd restart after terminating the observation-mode guard was also verified. Chrome was deliberately left open during testing; actual termination of the user's working Chrome session has not been tested.

Repeat the live fault test only in observation mode:

```sh
python3 focus-locks/macos-guard/tests/live-observation.py
```

References: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle), and [Cold Turkey's documented browser-closing behavior](https://getcoldturkey.com/support/user-guide/).
