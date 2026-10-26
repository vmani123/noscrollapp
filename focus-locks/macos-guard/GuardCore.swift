import Foundation

struct Health: Codable {
    let hostPID: Int32
    let browserPID: Int32
    let session: String
    let uptime: Double
    let windows: Int
    let siteAccess: Bool
    let incognito: Bool
    let version: String
}

struct BrowserSnapshot {
    let pid: Int32
    // nil means macOS window enumeration failed: do not silently allow the browser.
    let windowCount: Int?
    var profileCount: Int? = 1
}

enum GuardPolicy {
    static let checkInterval: Double = 60
    static let heartbeatLifetime: Double = 75
    static let startupGrace: Double = 60
    static let failureGrace: Double = 10

    static func problem(browser: BrowserSnapshot, reports: [Health], now: Double,
                        hostAlive: (Int32) -> Bool) -> String? {
        let live = reports.filter {
            $0.browserPID == browser.pid && $0.uptime <= now &&
            now - $0.uptime <= heartbeatLifetime && hostAlive($0.hostPID) &&
            $0.windows >= 0 && $0.windows <= 10000 && ["0.2.0", "0.3.0", "0.3.1"].contains($0.version)
        }
        guard !live.isEmpty else { return "The extension is missing, disabled, or not responding." }
        guard live.allSatisfy({ $0.siteAccess }) else {
            return "Allow the extension to run on all its requested sites, including LinkedIn."
        }
        guard live.allSatisfy({ $0.incognito }) else {
            return "Enable Allow in Incognito for the extension in every open profile."
        }
        guard let actual = browser.windowCount else { return "Chrome window protection could not be verified." }
        // A separate native connection exists for every running Chrome profile.
        // Count each host once; stale, duplicate files must not inflate coverage.
        var seen = Set<Int32>()
        let unique = live.filter { seen.insert($0.hostPID).inserted }
        guard let profiles = browser.profileCount, profiles > 0, unique.count >= profiles else {
            return "An active Chrome profile is not covered by the extension."
        }
        let protectedCount = unique.reduce(0) { $0 + $1.windows }
        // Chrome keeps many invisible autocomplete/tool-tip windows in WindowServer.
        // Compare visible browsing windows only. Hidden/minimized windows still
        // belong to the profile check above and are checked again when restored.
        guard protectedCount >= actual else {
            return "A Chrome window or profile is not covered by the extension."
        }
        return nil
    }
}

struct Enforcement {
    private(set) var started: Double?
    private(set) var unhealthySince: Double?
    private(set) var wasHealthy = false

    mutating func update(running: Bool, problem: String?, now: Double) -> Double? {
        guard running else {
            started = nil; unhealthySince = nil; wasHealthy = false
            return nil
        }
        if started == nil { started = now }
        guard problem != nil else { unhealthySince = nil; wasHealthy = true; return nil }
        if unhealthySince == nil { unhealthySince = now }
        let deadline = wasHealthy ? unhealthySince! + GuardPolicy.failureGrace
            : started! + GuardPolicy.startupGrace
        return max(0, deadline - now)
    }
}
