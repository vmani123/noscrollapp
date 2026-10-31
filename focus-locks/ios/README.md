# Locked Blocks for iPhone

**Perry branch, build 4:** Core and Extra now automatically include the native Threads and Facebook apps and their web domains, in addition to the existing Core defaults. See [Perry setup](../../PERRY-SETUP.md) for current installation instructions. The installation history below describes the original device, not Perry’s phone.

This is a native Screen Time blocker prototype, not a mockup. On October 15, 2026, the app and all three extensions were development-signed using Xcode 16.2 and installed on VikPhone (iPhone 17 Pro, iOS 26.6.1) through the USB installation-proxy service. The phone independently reports `com.local.lockedblocks.app` version 1.0 (1) as installed. **First launch, Screen Time authorization, blocking, and expiry still require physical-device testing.**

Source update, October 16, 2026: new blocks default to **1 hour, 0 minutes, 0 seconds**. Duration uses three scrolling wheels for hours/minutes/seconds, opened from the Duration button, with a Done button. The allowed total is 1 second to 7 days. New app downloads are allowed during a block. These source changes require rebuilding and updating the installed phone app; open the updated app once so reconciliation clears any installation restriction left by the previous version, including for an already-active block. Other Screen Time controls can still restrict downloads.

Update installed October 16, 2026: **version 1.0 (2)** was development-signed, installed over the existing app, and independently verified through the phone's installation service (`CFBundleVersion: 2`, profile validated). This version includes automatic native Reddit blocking during Extra windows, the one-hour default and hours/minutes/seconds fields, and allowed app downloads during blocks. Open the updated app once to reconcile its current restrictions. Installation is verified; physical blocking and expiry still need on-device checks.

Update installed October 16, 2026: **version 1.0 (3)** replaces typed duration fields with a Duration button and three scrolling wheels with Done, adds keyboard dismissal, and accepts totals from 1 second to 7 days. It includes foreground boundary cleanup, brief background execution for imminent short-block expiry, and an end-warning callback for short schedules. The signed app and all extensions built successfully; duration/boundary tests passed, and the phone independently reports build 3 with a validated profile. Precise short-block behavior and wheel interaction still require on-phone verification.

## Implemented

* Core and Extra app/category/website selections using Apple's privacy-preserving picker.
* Immediate or scheduled blocks lasting 1 second to 7 days, with scrolling hours/minutes/seconds wheels and a one-hour default, up to eight committed windows. The app also provides a keyboard Done button and interactive keyboard dismissal.
* Immutable selections and expiry for committed blocks; no cancel, pause, PIN, charger shortcut, emergency unlock, or shortening operation in the app.
* Profiles freeze while any committed block is pending or active. A later block cannot weaken an earlier one.
* Union of overlapping blocks: the end of one does not remove another active block.
* Device Activity extension applies restrictions at the scheduled start and recomputes them at the end, even while the app is closed. Opening the app also reconciles the current policy. Callback delivery and timing must be tested on the target iOS version.
* Active blocks set `denyAppRemoval`, which requests blocking deletion of **all apps**, not just this app. They clear this app's `denyAppInstallation` setting so new apps can be downloaded, and still require automatic date/time.
* Core defaults: Instagram, TikTok, Threads, and Facebook web domains. Threads and Facebook native apps are automatically blocked (hidden) during Core and Extra windows. Extra adds Reddit and all YouTube web domains and always blocks the native Reddit app (`com.reddit.Reddit`) using Managed Settings' built-in application block list. iOS hides that app while Extra is active. Other native apps, including YouTube, are selected through the picker.
* Shield buttons only close the blocked app/site.
* Atomic local persistence shared with the monitor, and a cross-process file lock around policy changes. An unreadable state does not silently clear an existing policy.

## Short-duration timing

Apple's [Device Activity monitoring interval](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort) must be at least 15 minutes. A shorter block keeps its true start/end in storage, uses a valid 15-minute monitoring interval, and sets its [end warning](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/warningtime) to the true expiry. Both the warning and the final interval end reconcile all active blocks; expired monitoring activities are removed so repeated short blocks do not accumulate registrations. While the app runs, a task wakes at exact start/end boundaries; for short blocks ending within 25 seconds it also requests brief background execution time. These requests and callbacks depend on iOS scheduling. One-second durations are accepted, but exact one-second enforcement/expiry while the app is suspended is best effort, not guaranteed; if the early callback is missed, the final monitor end or reopening the app also clears expired restrictions. Test on the phone before relying on very short blocks.

## The important boundary

The app deliberately omits early-exit features found in some existing blockers. Apple's [`denyAppRemoval`](https://developer.apple.com/documentation/managedsettings/applicationsettings/denyappremoval-swift.property) is the public API for normal deletion protection; reverse engineering isn't needed for that feature.

Self-management uses **individual Family Controls authorization**. The app cannot make its authorization irrevocable or give itself permission to control Settings permanently. Apple's [Family Controls documentation](https://developer.apple.com/documentation/familycontrols) describes stronger automatic deletion/iCloud protection for parent-authorized child accounts. This project does not misrepresent account eligibility.

On iOS 26.4 and later, [AppBlock's current guidance](https://appblock.app/help/apple/troubleshoot/) says a Screen Time passcode protects permission removal. A code and recovery controlled outside your access add practical resistance. If you know the code or can recover it, that isn't an independent lock. Supervised management is a separate deployment if OS-level permission revocation must be prevented; this application alone does not implement it.

Shorts-only filtering in the native YouTube app is **not implemented**. Extra automatically blocks the Reddit app and websites, and blocks all YouTube when its app is selected. Core has an explicit option to block YouTube websites too, but you must also select the native app for whole-YouTube blocking. It never labels a domain block as Shorts-only protection. Website behavior must be checked across browsers, private modes, and embedded web views.

## Install on your phone

**Successful installation without an OS upgrade, October 15, 2026:** after registering the phone with the developer team, all four development profiles were generated with Family Controls enabled. The signed app passed `codesign --verify --deep --strict` with normal keychain access. A direct target build avoided Xcode's device-preparation step:

```sh
xcodebuild -project LockedBlocks.xcodeproj -target LockedBlocks \
  -configuration Debug -sdk iphoneos -arch arm64 \
  SYMROOT=../build/ios-signed OBJROOT=../build/ios-signed-objects \
  -allowProvisioningUpdates build -quiet
```

The bundle and its embedded profiles/extensions were packaged as `../build/LockedBlocks-development.ipa` under `Payload/LockedBlocks.app`. Exclude AppleDouble `._*` metadata from the ZIP: the first package containing that metadata was rejected. A temporary isolated PyMobileDevice3 environment at `/private/tmp/lockedblocks-install-venv` installed the corrected package with `pymobiledevice3 apps install --developer --udid <phone-UDID> <ipa-path>`. Installation reached 100% and reported success; an independent installation-proxy lookup confirmed the app. This uses the existing paired USB connection and does not mount the developer image. It does not start a block. The temporary environment may need recreating after a restart. Xcode Run/debugging remains blocked by the DDI error below, but a macOS/Xcode upgrade was **not required for this installation**.

**Device preparation diagnosis, October 15, 2026:** the connected device is an iPhone 17 Pro running iOS 26.6.1. With macOS 14.6.1 and Xcode 16.2, the developer image cannot mount (`0xe800010f`, missing hardware variant). Apple's official `xcodebuild -runFirstLaunch -checkForNewerComponents` completed and updated the selected image from build `16C5032a` to `16C7015`, but a direct `devicectl device info ddiServices` retry reproduced the error. Developer Program membership does not fix this device-support failure. Use a newer Xcode; Apple's [compatibility table](https://developer.apple.com/xcode/system-requirements/) lists Xcode 26.3 as compatible with macOS Sequoia 15.6 through Tahoe 26.x. That is an option without requiring the latest Xcode/macOS combination. The Mac needs a compatible macOS update before running that version; no macOS or full Xcode upgrade has been performed.

1. Open `LockedBlocks.xcodeproj` in Xcode. If you change `project.yml`, regenerate with `xcodegen generate`.
2. Select a valid Apple Developer Program signing team. This Mac now has a valid Apple Development signing identity, and the phone is registered with that team. The app and three extension identifiers must support Family Controls; the app and monitor must also share the App Group `group.com.local.lockedblocks`. Choose unique identifiers for your team and update the group string in `Shared/LockStore.swift` if necessary.
3. Connect your iPhone, select it as the run destination, complete any required developer-mode setup, and run from Xcode. Xcode 16.2 is installed here; if your phone runs a newer iOS version, a compatible Xcode/platform installation may be required.
4. Approve Screen Time on the phone. Choose Instagram and TikTok in Core. Reddit is automatically included in Extra; choose the YouTube app and any additional apps in its picker. Select any additional web domains through the picker where needed. Do not select Locked Blocks or essential apps you need during the block.
5. Verify a short Core block first and check the native apps, domains, deletion protection, allowed App Store downloads, and expiration. Add a short Extra block to verify Reddit/YouTube. Test with the app closed and after restarting the phone before attempting a week.

For TestFlight/App Store distribution, Apple requires approval of the [Family Controls distribution entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) for the app and Screen Time extensions. Development signing is a separate route. Unsigned `.app` files cannot simply be copied onto a normal iPhone. Provisioning/certificate expiry also needs to be accounted for before relying on a long block.

## Verification performed

The app plus monitor, shield configuration, and shield action extensions built successfully with signing disabled. Foundation-only tests passed for start/end boundaries, the 168-hour limit, invalid durations, overlap, and validated persistence. These results verify source compilation and window logic, not iOS enforcement.

Build without choosing a connected device:

```sh
xcodebuild -project LockedBlocks.xcodeproj -target LockedBlocks \
  -configuration Release -sdk iphoneos -arch arm64 \
  SYMROOT=../build/ios-target OBJROOT=../build/ios-objects \
  CODE_SIGNING_ALLOWED=NO build
```

The scheme's generic device build on this Mac reported that the iOS 18.2 platform support was not installed. A direct target build against the existing SDK succeeded. The unsigned output is `../build/ios-target/Release-iphoneos/LockedBlocks.app`.

### Physical device diagnosis, October 15, 2026

VikPhone is an iPhone 17 Pro running iOS 26.6.1. Apple's device service reports it **paired**, connected by **wired** transport with the tunnel **connected**, and Developer Mode **enabled**. The remaining failure is developer-device preparation: `ddiServicesAvailable` is false. A query of DDI services fails with CoreDevice error 12040 and `kAMDMobileImageMounterPersonalizedBundleMissingVariantError`: the installed image lacks the required hardware variant. The installed DDI is build 16C7015 with CoreDevice 397.30, from Xcode 16.2.

The official `xcodebuild -runFirstLaunch -checkForNewerComponents` command completed successfully, but the same hardware-variant error remained on retest. Repeated trust/pairing steps do not address this specific error. A supported next route is a newer Xcode with iPhone 17 support, on a compatible macOS version. For example, Apple's [compatibility table](https://developer.apple.com/xcode/system-requirements/) lists Xcode 26.3 for macOS Sequoia 15.6 through Tahoe 26.x. This Mac currently runs macOS 14.6.1, so that route requires a macOS upgrade or a different compatible Mac. No macOS upgrade has been performed.

Run the independent timing tests from the `focus-locks` directory:

```sh
xcrun swiftc -module-cache-path /private/tmp/locked-blocks-swift-cache \
  ios/Shared/LockWindow.swift ios/Tests/main.swift \
  -o /private/tmp/locked-blocks-window-tests
/private/tmp/locked-blocks-window-tests
```

Required physical-device checks include: committed selections cannot change; no early-exit UI; permissions revocation behavior on your iOS version; all-app removal protection; all installed browsers; Wi-Fi/cellular; immediately active and scheduled starts; overlapping ends; clock changes; restart while active; automatic restoration at expiry with the app closed; and multi-day scheduling across midnight and daylight-saving changes. The code does not claim these have passed.
