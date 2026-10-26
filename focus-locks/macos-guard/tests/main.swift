import Foundation

var checks = 0
func check(_ condition: Bool, _ label: String) {
    checks += 1
    if !condition { fatalError("FAIL: \(label)") }
}
func health(pid: Int32 = 5, host: Int32 = 7, time: Double = 100, windows: Int = 1,
            site: Bool = true, incognito: Bool = true, version: String = "0.2.0") -> Health {
    Health(hostPID: host, browserPID: pid, session: "session", uptime: time,
           windows: windows, siteAccess: site, incognito: incognito, version: version)
}
func problem(_ reports: [Health], windows: Int? = 1, alive: Bool = true) -> String? {
    GuardPolicy.problem(browser: BrowserSnapshot(pid: 5, windowCount: windows), reports: reports,
                        now: 100, hostAlive: { _ in alive })
}
check(problem([health()]) == nil, "working extension")
check(problem([]) != nil, "missing or disabled extension")
check(problem([health(time: 100 - GuardPolicy.heartbeatLifetime - 1)]) != nil, "stale heartbeat")
check(problem([health(time: 101)]) != nil, "future heartbeat")
check(problem([health()], alive: false) != nil, "dead native host")
check(problem([health(pid: 6)]) != nil, "other browser process is not coverage")
check(problem([health(site: false)]) != nil, "revoked site access")
check(problem([health(incognito: false)]) != nil, "private access required")
check(problem([health(version: "0.1.0")]) != nil, "old extension rejected")
check(problem([health(version: "0.3.0")]) == nil, "LinkedIn-enabled extension accepted")
check(problem([health(version: "0.3.1")]) == nil, "LinkedIn message/connection update accepted")
check(problem([health()], windows: nil) != nil, "failed OS window query")
check(problem([health()], windows: 2) != nil, "second unprotected profile")
check(problem([health(), health(host: 8)], windows: 2) == nil, "two protected profiles")
check(problem([health(), health()], windows: 2) != nil, "duplicate report not extra coverage")
check(problem([health(windows: 0)], windows: 0) == nil, "browser with no windows")
check(problem([health(windows: 3)], windows: 2) == nil, "minimized and other-space windows are not visible")
check(problem([health(), health(host: 8, incognito: false)], windows: 2) != nil, "one bad profile")
check(GuardPolicy.problem(browser: BrowserSnapshot(pid: 5, windowCount: 1, profileCount: 2),
                          reports: [health(windows: 3)], now: 100, hostAlive: { _ in true }) != nil,
      "one profile with many windows cannot cover a second profile")
check(GuardPolicy.problem(browser: BrowserSnapshot(pid: 5, windowCount: 1, profileCount: nil),
                          reports: [health()], now: 100, hostAlive: { _ in true }) != nil,
      "unreadable profile state fails closed")

var state = Enforcement()
check(state.update(running: false, problem: "missing", now: 0) == nil, "nothing to close")
check(state.update(running: true, problem: "missing", now: 10) == 60, "startup grace")
check(state.update(running: true, problem: "missing", now: 69) == 1, "countdown")
check(state.update(running: true, problem: "missing", now: 70) == 0, "close at deadline")
check(state.update(running: true, problem: nil, now: 71) == nil, "restored extension")
check(state.update(running: true, problem: "disabled", now: 72) == 10, "short grace after disable")
check(state.update(running: true, problem: "disabled", now: 82) == 0, "close disabled browser")
check(state.update(running: true, problem: nil, now: 83) == nil, "recovery cancels close")
check(state.update(running: false, problem: nil, now: 84) == nil, "reset after quit")
check(state.update(running: true, problem: "missing", now: 85) == 60, "relaunch repair interval")
let data = try JSONEncoder().encode(health())
check(try JSONDecoder().decode(Health.self, from: data).windows == 1, "native report round trip")
print("Passed \(checks) guard checks.")
