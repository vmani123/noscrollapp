import SwiftUI
import FamilyControls
import UIKit

@MainActor
final class BlockModel: ObservableObject {
    @Published var core = FamilyActivitySelection()
    @Published var extra = FamilyActivitySelection()
    @Published var blocks: [LockedBlock] = []
    @Published var authorization = AuthorizationCenter.shared.authorizationStatus
    @Published var error: String?
    @Published var mode = BlockMode.core
    @Published var duration = BlockDuration()
    @Published var startLater = false
    @Published var startsAt = Date().addingTimeInterval(3600)
    @Published var wholeYouTube = false
    @Published var now = Date()
    @Published var committing = false
    private var boundaryTask: Task<Void, Never>?
    private var expiryBackgroundTask = UIBackgroundTaskIdentifier.invalid

    var profilesLocked: Bool { blocks.contains { $0.window.isCommitted(at: now) } }
    var active: [LockedBlock] { blocks.filter { $0.window.isActive(at: now) } }
    var pending: [LockedBlock] { blocks.filter { $0.window.isCommitted(at: now) } }

    init() { refresh(reloadProfiles: true) }

    func refresh(reloadProfiles: Bool = false) {
        now = Date()
        authorization = AuthorizationCenter.shared.authorizationStatus
        do {
            try LockStore.reconcile()
            let state = try LockStore.load()
            blocks = state.blocks.sorted { $0.window.start < $1.window.start }
            if reloadProfiles {
                core = state.core
                extra = state.extra
            }
            scheduleBoundaryRefresh()
        } catch { self.error = error.localizedDescription }
    }

    private func scheduleBoundaryRefresh() {
        boundaryTask?.cancel()
        let date = Date()
        let expiresSoon = blocks.contains {
            let remaining = $0.window.end.timeIntervalSince(date)
            return remaining > 0 && remaining <= 25
                && $0.window.end.timeIntervalSince($0.window.start) < LockWindow.minimumMonitoringDuration
        }
        if expiresSoon && expiryBackgroundTask == .invalid {
            // Ask iOS for brief execution time so leaving this screen does not
            // immediately suspend a one-second block's cleanup task.
            expiryBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Block expiry") { [weak self] in
                self?.finishExpiryBackgroundTask()
            }
        } else if !expiresSoon {
            finishExpiryBackgroundTask()
        }
        guard let next = blocks.flatMap({ [$0.window.start, $0.window.end] }).filter({ $0 > date }).min() else {
            boundaryTask = nil
            return
        }
        let delay = UInt64(max(0, next.timeIntervalSinceNow) * 1_000_000_000)
        boundaryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func finishExpiryBackgroundTask() {
        guard expiryBackgroundTask != .invalid else { return }
        let identifier = expiryBackgroundTask
        expiryBackgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }

    func tick() {
        let date = Date()
        let changed = Set(active.map(\.id)) != Set(blocks.filter { $0.window.isActive(at: date) }.map(\.id))
        now = date
        if changed || authorization != AuthorizationCenter.shared.authorizationStatus { refresh() }
    }

    func authorize() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            error = nil
            refresh(reloadProfiles: true)
        } catch { self.error = error.localizedDescription }
    }

    func saveProfiles() {
        do { try LockStore.saveProfiles(core: core, extra: extra); error = nil }
        catch { self.error = error.localizedDescription; refresh(reloadProfiles: true) }
    }

    func commit() {
        committing = true
        defer { committing = false }
        do {
            guard let seconds = duration.timeInterval else { throw LockWindow.WindowError.invalidDuration }
            // The one-second boundary is representable by Device Activity's date components.
            let start = Date(timeIntervalSince1970: ceil((startLater ? max(Date(), startsAt) : Date()).timeIntervalSince1970))
            let window = try LockWindow(start: start, end: start.addingTimeInterval(seconds))
            try LockStore.commit(window: window, mode: mode, wholeYouTube: wholeYouTube)
            error = nil
            refresh(reloadProfiles: true)
        } catch { self.error = error.localizedDescription }
    }
}
