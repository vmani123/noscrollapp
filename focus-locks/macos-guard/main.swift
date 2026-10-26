import AppKit
import CoreGraphics
import Darwin

let fm = FileManager.default
let stateRoot = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Intentional Browsing Guard")
let reportRoot = stateRoot.appendingPathComponent("health", isDirectory: true)
let extensionID = Bundle.main.object(forInfoDictionaryKey: "IBExtensionID") as? String ?? ""
let chromeBundle = "com.google.Chrome"

func prepareState() throws {
    try fm.createDirectory(at: reportRoot, withIntermediateDirectories: true,
                           attributes: [.posixPermissions: 0o700])
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateRoot.path)
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try JSONEncoder().encode(value).write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func readExact(_ count: Int, deadline: Double) -> Data? {
    var data = Data()
    while data.count < count {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if remaining <= 0 { return nil }
        var fd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let result = poll(&fd, 1, Int32(min(remaining * 1000, 1000)))
        if result < 0 { if errno == EINTR { continue }; return nil }
        if result == 0 { continue }
        if (fd.revents & Int16(POLLIN)) == 0 { return nil }
        var buffer = [UInt8](repeating: 0, count: count - data.count)
        let received = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
        if received <= 0 { return nil }
        data.append(contentsOf: buffer.prefix(received))
    }
    return data
}

func nativeMessage(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value)
    var size = UInt32(data.count).littleEndian
    try FileHandle.standardOutput.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) })
    try FileHandle.standardOutput.write(contentsOf: data)
}

func nativeHost() throws {
    // Chrome supplies the calling extension origin; no web-accessible HTTP endpoint exists.
    guard CommandLine.arguments.dropFirst().first == "chrome-extension://\(extensionID)/" else { exit(2) }
    let parent = getppid()
    guard NSRunningApplication(processIdentifier: parent)?.bundleIdentifier == chromeBundle else { exit(3) }
    try prepareState()
    let session = UUID().uuidString
    let file = reportRoot.appendingPathComponent("\(getpid())-\(session).json")
    defer { try? fm.removeItem(at: file) }
    while getppid() == parent {
        let nonce = UUID().uuidString
        try nativeMessage(["type": "challenge", "nonce": nonce])
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        guard let header = readExact(4, deadline: deadline) else { return }
        let size = header.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
        guard size > 0, size <= 65536,
              let data = readExact(Int(size), deadline: deadline),
              let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["type"] as? String == "health", message["nonce"] as? String == nonce,
              message["extensionID"] as? String == extensionID,
              let windows = message["windows"] as? Int, windows >= 0, windows <= 10000,
              let siteAccess = message["siteAccess"] as? Bool,
              let incognito = message["incognito"] as? Bool,
              let version = message["version"] as? String else { return }
        try writeJSON(Health(hostPID: getpid(), browserPID: parent, session: session,
                             uptime: ProcessInfo.processInfo.systemUptime, windows: windows,
                             siteAccess: siteAccess, incognito: incognito, version: version), to: file)
        Thread.sleep(forTimeInterval: GuardPolicy.checkInterval)
    }
}

func loadReports() -> [Health] {
    let files = (try? fm.contentsOfDirectory(at: reportRoot, includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == "json" }.compactMap {
        guard let data = try? Data(contentsOf: $0) else { return nil }
        return try? JSONDecoder().decode(Health.self, from: data)
    }
}

func chromeWindows(pid: Int32) -> Int? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { return nil }
    return windows.filter {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
        ($0[kCGWindowLayer as String] as? Int) == 0 &&
        (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) >= 100 &&
        (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) >= 100
    }.count
}

func chromeProfileCount() -> Int? {
    let file = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
    guard let data = try? Data(contentsOf: file),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let profile = root["profile"] as? [String: Any],
          let active = profile["last_active_profiles"] as? [String], !active.isEmpty else { return nil }
    return Set(active).count
}

struct Status: Codable {
    let running: Bool
    let observing: Bool
    let problem: String?
    let secondsRemaining: Int?
    var checkedAt: Double = ProcessInfo.processInfo.systemUptime
    var checkInterval: Double = GuardPolicy.checkInterval
}

final class GuardApp: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var panel: NSPanel!
    var message: NSTextField!
    var timer: Timer?
    var enforcement: [Int32: Enforcement] = [:]
    var terminated: Set<Int32> = []
    var lastStatus: Status?
    let observing = CommandLine.arguments.contains("--observe")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try prepareState() } catch { fputs("Cannot create guard state: \(error)\n", stderr); exit(1) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "IB"
        let menu = NSMenu()
        let status = NSMenuItem(title: "Extension protection status", action: #selector(showStatus), keyEquivalent: "")
        status.target = self; menu.addItem(status)
        item.menu = menu
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 530, height: 230),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Intentional Browsing Guard"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        let title = NSTextField(labelWithString: "Chrome needs the feed blocker.")
        title.font = .boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: 24, y: 179, width: 480, height: 28)
        message = NSTextField(wrappingLabelWithString: "")
        message.frame = NSRect(x: 24, y: 20, width: 480, height: 150)
        message.font = .systemFont(ofSize: 14)
        panel.contentView?.addSubview(title); panel.contentView?.addSubview(message)
        panel.center()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: GuardPolicy.checkInterval, repeats: true) { [weak self] _ in self?.tick() }
    }

    @objc func showStatus() {
        render(lastStatus ?? Status(running: false, observing: observing, problem: nil, secondsRemaining: nil))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func render(_ status: Status) {
        if let problem = status.problem {
            let timing = status.observing ? "Observation mode: Chrome will stay open."
                : "Chrome closes in \(status.secondsRemaining ?? 0) seconds."
            message.stringValue = "\(problem)\n\n\(timing)\n\nOpen chrome://extensions in the affected profile. Install Intentional Browsing, enable it, and select Allow in Incognito and access to all requested sites."
        } else {
            message.stringValue = status.running ? "The extension is responding and covers Chrome's current windows."
                : "Protection is running. Chrome will be checked when you open it."
        }
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundle)
        let pids = Set(apps.map { $0.processIdentifier })
        enforcement = enforcement.filter { pids.contains($0.key) }
        terminated = terminated.intersection(pids)
        let reports = loadReports()
        var result = Status(running: !apps.isEmpty, observing: observing, problem: nil, secondsRemaining: nil)
        for app in apps {
            let pid = app.processIdentifier
            let problem = GuardPolicy.problem(browser: BrowserSnapshot(pid: pid, windowCount: chromeWindows(pid: pid),
                                                                        profileCount: chromeProfileCount()),
                                              reports: reports, now: now, hostAlive: { kill($0, 0) == 0 })
            var state = enforcement[pid] ?? Enforcement()
            let remaining = state.update(running: true, problem: problem, now: now)
            enforcement[pid] = state
            if let problem = problem, let remaining = remaining {
                let nextCheck = ceil(remaining / GuardPolicy.checkInterval) * GuardPolicy.checkInterval
                result = Status(running: true, observing: observing, problem: problem, secondsRemaining: Int(nextCheck))
                if remaining <= 0 && !observing {
                    // Request a normal browser exit first. Enforce on the next tick if Chrome refuses.
                    if terminated.contains(pid) { app.forceTerminate() }
                    else { app.terminate(); terminated.insert(pid) }
                }
            } else { terminated.remove(pid) }
        }
        let changed = lastStatus?.problem != result.problem
        lastStatus = result
        try? writeJSON(result, to: stateRoot.appendingPathComponent("status.json"))
        render(result)
        if result.problem != nil && changed && !observing {
            panel.orderFrontRegardless()
        } else if result.problem == nil { panel.orderOut(nil) }
    }
}

if CommandLine.arguments.dropFirst().first?.hasPrefix("chrome-extension://") == true {
    do { try nativeHost() } catch { fputs("Native host: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--status") {
    if let data = try? Data(contentsOf: stateRoot.appendingPathComponent("status.json")) {
        FileHandle.standardOutput.write(data); print("")
    } else { print("Guard is not running or has not written status yet.") }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = GuardApp()
    app.delegate = delegate
    app.run()
}
