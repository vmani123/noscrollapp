import DeviceActivity
import OSLog

final class BlockMonitor: DeviceActivityMonitor {
    private let log = Logger(subsystem: "com.local.lockedblocks", category: "monitor")
    private func refreshPolicy() {
        do { try LockStore.reconcile() }
        catch { log.error("Policy reconciliation failed: \(error.localizedDescription, privacy: .public)") }
    }
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        refreshPolicy()
    }
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Recompute all active windows, so one ending block cannot remove an overlapping block.
        refreshPolicy()
    }
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        // Short blocks use the end warning at their actual expiry.
        refreshPolicy()
    }
}
