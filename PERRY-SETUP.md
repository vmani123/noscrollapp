# Perry setup: Threads and Facebook in Core

This branch adds Threads and Facebook to the existing iPhone Core baseline. During any active Core or Extra block, the native Threads (`com.burbn.barcelona`) and Facebook (`com.facebook.Facebook`) apps are hidden and cannot launch. Core also includes instagram.com, tiktok.com, threads.com, threads.net, facebook.com, fb.com, and fb.watch. Select the Instagram and TikTok native apps in the phone's Core picker, as before. Extra inherits Core and retains Reddit and YouTube behavior.

The native app identifiers were checked against Apple's public lookup API for app IDs 6446901002 and 284882215. These are whole-app blocks. Facebook Messenger is a separate app and is not automatically included. The new app/site restrictions clear with this app's other settings after the final active block expires. Verify actual enforcement on the friend's phone before relying on it.

On the Mac, Threads is fully blocked in Chrome at the network level (threads.com, threads.net, and subdomains), alongside feed restrictions on YouTube, Reddit, and Bilibili and the LinkedIn gate. Threads is blocked continuously in Chrome; it does not follow the iPhone timer. Facebook's new rule applies to the iPhone app. The Mac guard requires the extension's network-blocking permission and site access. Firefox receives a page shield fallback rather than the Chrome network rules; the Mac guard enforces Chrome only.

## Friend's Mac: Chrome extension

Requirements: macOS 14 or newer for the guard, Google Chrome 120 or newer, Python 3, and Xcode Command Line Tools (or full Xcode). The guard uses Apple's local Swift compiler and ad-hoc signing. No paid developer membership is needed for these Mac components. Use full Xcode on whichever Mac builds the iPhone app.

1. Install Apple's Command Line Tools if needed: `xcode-select --install`. Verify `git --version`, `python3 --version`, and `xcrun swiftc --version`. If Python 3 is missing, install it from [python.org](https://www.python.org/downloads/macos/).
2. Clone into a permanent folder in the friend's account; avoid Downloads or temporary folders. If the repository is private, grant their GitHub account read access first.

   ```sh
   mkdir -p "$HOME/Developer"
   cd "$HOME/Developer"
   git clone --branch codex/perry https://github.com/vmani123/noscrollapp.git
   cd noscrollapp
   python3 focus-locks/build-packages.py
   ```

3. In each Chrome profile they use, open `chrome://extensions`, enable Developer mode, select **Load unpacked**, and select the clone's `focus-locks/packages/chromium` folder.
4. Open the extension's **Details**. Enable **Allow in Incognito** and site access to all requested YouTube, Reddit, Bilibili (including b23.tv), LinkedIn, and Threads domains. Refresh already-open tabs, including any existing Threads tabs. The extension removes feeds/Shorts/recommendations while retaining deliberate YouTube search/video, Bilibili search/direct video, and individual Reddit thread access; LinkedIn uses its notification gate. On Bilibili, search requires a nonempty keyword, direct BV/av videos and valid player embeds are allowed, and home/dynamic/ranking/profile/live feeds are blocked. Recommendation and next-video controls are hidden on video pages, unsolicited playback is paused, and automatic SPA next-video transitions are shielded. Scrolling through an opened video’s comments remains available.

## Friend's Mac: guard

Run all commands from the clone's root, in the friend's logged-in account, without sudo.

1. Start observation mode first:

   ```sh
   python3 focus-locks/macos-guard/install.py --observe
   ```

2. Reload the extension in **each profile** after the native messaging host has been installed. Use the `IB` menu-bar item to check protection, or run:

   ```sh
   "$HOME/Applications/Intentional Browsing Guard.app/Contents/MacOS/BrowserGuard" --status
   ```

   Wait for a fresh status with `observing: true` and no problem. The checks run every 60 seconds. Exercise the profiles, private windows, and other windows they use. Resolve missing permissions or profiles before continuing.
3. Save browser work, then enable enforcement:

   ```sh
   python3 focus-locks/macos-guard/install.py
   ```

   The installer requires a healthy status less than 75 seconds old. If it refuses, return to observation mode and fix the reported problem. Check the status again and confirm `observing: false` with no problem.
4. With browser work saved, disable the extension once to verify the guard warns and closes Chrome after its grace/check cycle. Reopen Chrome and re-enable it promptly. Check that threads.com and threads.net, direct post links, and private-window visits are all blocked. Also test Bilibili: home, dynamic feed, rankings, and profiles should be shielded; keyword search and a direct video should work; recommendations and unsolicited playback should be suppressed. Verify YouTube searches/videos and Reddit posts still work. Log out/in and verify the guard restarts and reports healthy.

The installer builds for their Mac, installs `~/Applications/Intentional Browsing Guard.app`, and registers its own login agent and Chrome native host. Do not copy your prebuilt guard/native-host JSON: the extension ID is derived from the **absolute package path**, and the host's executable path is account-specific. Keep the clone in place; rebuild/reinstall the guard if it moves. The guard only enforces Google Chrome and can close every window in its process. It is a user-controlled companion, not an administrator-proof lock.

For intentional removal: `python3 focus-locks/macos-guard/install.py --uninstall`. Remove the extension separately through Chrome. The `.command` observation/enforcement helpers are alternatives to the commands above.

## Friend's iPhone: development installation

The branch is source code, not an installable iPhone package. For one friend, use a development-signed build on their registered test phone. You can do this from **your Mac** using your existing paid Apple Developer Program team; they do not need their own paid membership or your signing keys. Their Mac only needs full Xcode if it will do the iPhone building/signing itself.

1. Use full Xcode with support for their iPhone/iOS version, and an active paid team with Family Controls development capability. Connect their phone by USB, approve Trust, register it with the team, and enable Developer Mode if prompted. Xcode must have signing access to that team. Apple documents [development profiles and registered devices](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/).
2. Open `focus-locks/ios/LockedBlocks.xcodeproj`. Choose the appropriate team under **Signing & Capabilities** for **all four targets**: LockedBlocks, BlockMonitor, BlockShield, and BlockShieldAction. Enable automatic signing or generate development profiles including their phone for all targets. All four require Family Controls; the app and monitor also need the same App Group.
3. When building with the existing owner's team, the existing bundle IDs and `group.com.local.lockedblocks` can be reused on the friend's separate device. With another developer team, choose identifiers available to that team; update `project.yml`, regenerate with XcodeGen, and update `LockStore.group` and the app/monitor entitlement group values consistently. Simply selecting a different team does not transfer identifier ownership.
4. Select their phone as the run destination and build/run. Build 4 identifies this branch's customization. A previously signed IPA for your phone is insufficient unless its profiles also include theirs. Do not send certificates, private keys, Apple account passwords, or your Xcode user data. Keep signed IPAs out of Git.
5. Launch **Locked Blocks**, authorize Screen Time, and open Core's picker to select Instagram/TikTok and any other desired native apps. Threads/Facebook are built in and do not need picker selection. Picker selections belong on their phone; do not copy your saved selection state.
6. Commit a **15-minute Core test**, verify Threads/Facebook cannot launch and the listed websites are blocked, and verify selected Instagram/TikTok apps. Check the browsers they actually use. The hidden native apps should become available after expiry. Test expiry with Locked Blocks closed, then test an Extra block and overlapping Core/Extra blocks. Verify restart behavior before relying on long blocks.

Active blocks request prevention of deletion of **all apps**, while allowing new downloads. Committed blocks have no in-app early cancellation. Individual Screen Time authorization is still revocable in iOS. These restrictions should be understood by the friend before committing a test block. Development profiles/certificates expire: check their actual expiry and arrange a signed update before it, especially before multi-day blocks.

For convenient remote updates later, TestFlight is an alternative after Apple approves Family Controls **distribution** for the app and each Screen Time extension; external testing has its own review requirements. Ad hoc distribution also requires appropriate distribution profiles and entitlement provisioning support. Development signing does not imply those distribution approvals. See [Apple's entitlement request instructions](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement). No signing or physical-device verification for this friend's phone has been performed by preparing this branch.

## Updates

Keep the friend on this branch and use `git pull --ff-only`. After browser changes, rebuild packages and Reload in every profile; reinstall the guard if its code, registration, or package location changes. iPhone changes require a new signed build and installation. Pulling source does not update the installed iPhone app. A separate branch does not require a separate Apple bundle ID or a new developer account.

## Validation of this branch

Unsigned iPhone build 4 and all three extensions compiled successfully. The 68 URL policy cases, Bilibili playback/automatic-navigation checks, existing LinkedIn and native worker checks, 31 guard policy checks, and iPhone duration/boundary tests passed. Browser packages were regenerated from source. These checks do not verify current live Bilibili layouts or enforcement on Perry’s hardware; perform the installation checks above, including ordinary/private browsing and expiry on the phone.
