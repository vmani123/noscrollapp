import Foundation
import Darwin
import FamilyControls
import ManagedSettings
import DeviceActivity

enum BlockMode: String, Codable, CaseIterable, Identifiable {
    case core, extra
    var id: String { rawValue }
    var title: String { self == .core ? "Core" : "Extra" }
}

struct LockedBlock: Codable, Identifiable {
    let id: UUID
    let window: LockWindow
    let mode: BlockMode
    let selection: FamilyActivitySelection
    // Policies are snapshots. Changing a future profile cannot weaken a committed block.
    let blockWholeYouTube: Bool
    var activity: DeviceActivityName { DeviceActivityName("locked-block-" + id.uuidString) }
}

struct SavedState: Codable {
    var core = FamilyActivitySelection()
    var extra = FamilyActivitySelection()
    var blocks: [LockedBlock] = []
}

enum LockStore {
    static let group = "group.com.local.lockedblocks"
    static let settings = ManagedSettingsStore(named: .init("locked-blocks"))

    enum StoreError: LocalizedError {
        case unavailable, lockedProfiles, tooManyBlocks, unauthorized
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Shared storage is unavailable. Check App Group signing."
            case .lockedProfiles: return "Profiles cannot change until committed blocks finish."
            case .tooManyBlocks: return "Finish a committed block before adding more."
            case .unauthorized: return "Authorize Screen Time before committing a block."
            }
        }
    }

    private static func folder() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw StoreError.unavailable
        }
        return url
    }

    // Serialize state changes and settings updates across the app and monitor process.
    private static func transaction<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = try folder()
        let fd = open(directory.appendingPathComponent("policy.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw StoreError.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StoreError.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try body(directory.appendingPathComponent("state.json"))
    }

    private static func read(_ url: URL) throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }

    private static func write(_ state: SavedState, to url: URL) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() throws -> SavedState { try transaction { try read($0) } }

    static func saveProfiles(core: FamilyActivitySelection, extra: FamilyActivitySelection) throws {
        try transaction { url in
            var state = try read(url)
            guard !state.blocks.contains(where: { $0.window.isCommitted(at: Date()) }) else {
                throw StoreError.lockedProfiles
            }
            state.core = core
            state.extra = extra
            try write(state, to: url)
        }
    }

    static func commit(window: LockWindow, mode: BlockMode, wholeYouTube: Bool) throws {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else { throw StoreError.unauthorized }
        try transaction { url in
            var state = try read(url)
            let expired = state.blocks.filter { !$0.window.isCommitted(at: Date()) }.map(\.activity)
            state.blocks.removeAll { !$0.window.isCommitted(at: Date()) }
            guard state.blocks.count < 8 else { throw StoreError.tooManyBlocks }
            let prior = state
            var selection = state.core
            if mode == .extra {
                selection.applicationTokens.formUnion(state.extra.applicationTokens)
                selection.categoryTokens.formUnion(state.extra.categoryTokens)
                selection.webDomainTokens.formUnion(state.extra.webDomainTokens)
            }
            let block = LockedBlock(id: UUID(), window: window, mode: mode,
                                    selection: selection, blockWholeYouTube: wholeYouTube || mode == .extra)
            state.blocks.append(block)
            // Persist before registering so a callback can always find its immutable snapshot.
            try write(state, to: url)
            if !expired.isEmpty { DeviceActivityCenter().stopMonitoring(expired) }
            let calendar = Calendar.current
            func components(_ date: Date) -> DateComponents {
                var value = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
                value.calendar = calendar
                value.timeZone = calendar.timeZone
                return value
            }
            let schedule = DeviceActivitySchedule(intervalStart: components(window.start),
                                                  intervalEnd: components(window.monitoringEnd), repeats: false,
                                                  warningTime: window.expiryWarning)
            do {
                try DeviceActivityCenter().startMonitoring(block.activity, during: schedule)
            } catch {
                DeviceActivityCenter().stopMonitoring([block.activity])
                try write(prior, to: url)
                apply(prior, at: Date())
                throw error
            }
            apply(state, at: Date())
        }
    }

    static func reconcile() throws {
        try transaction { url in
            var state = try read(url)
            let now = Date()
            let expired = state.blocks.filter { !$0.window.isCommitted(at: now) }.map(\.activity)
            if !expired.isEmpty {
                state.blocks.removeAll { !$0.window.isCommitted(at: now) }
                // Prune first so a stop callback cannot repeatedly stop the same activity.
                try write(state, to: url)
            }
            apply(state, at: now)
            if !expired.isEmpty { DeviceActivityCenter().stopMonitoring(expired) }
        }
    }

    private static func apply(_ state: SavedState, at now: Date) {
        let active = state.blocks.filter { $0.window.isActive(at: now) }
        guard !active.isEmpty else {
            // Only this app's named store is cleared; other blockers retain their policies.
            settings.clearAllSettings()
            return
        }
        var selection = FamilyActivitySelection()
        var domains = Set(["instagram.com", "tiktok.com", "threads.com", "threads.net",
                           "facebook.com", "fb.com", "fb.watch"].map { WebDomain(domain: $0) })
        for block in active {
            selection.applicationTokens.formUnion(block.selection.applicationTokens)
            selection.categoryTokens.formUnion(block.selection.categoryTokens)
            selection.webDomainTokens.formUnion(block.selection.webDomainTokens)
            if block.blockWholeYouTube {
                domains.formUnion(["youtube.com", "youtu.be", "youtube-nocookie.com"].map { WebDomain(domain: $0) })
            }
            if block.mode == .extra {
                domains.formUnion(["reddit.com", "redd.it"].map { WebDomain(domain: $0) })
            }
        }
        settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        settings.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        // This friend's Core baseline includes Threads and Facebook without picker tokens.
        // Extra inherits Core. Recompute the union so an overlapping Extra expiry
        // removes Reddit while retaining Core apps until the last active block ends.
        var blockedApps: Set<Application> = [Application(bundleIdentifier: "com.burbn.barcelona"),
                                             Application(bundleIdentifier: "com.facebook.Facebook")]
        if active.contains(where: { $0.mode == .extra }) {
            blockedApps.insert(Application(bundleIdentifier: "com.reddit.Reddit"))
        }
        settings.application.blockedApplications = blockedApps
        settings.webContent.blockedByFilter = .specific(domains)
        settings.application.denyAppRemoval = true
        // Clear this app's previous installation restriction, including during
        // an existing block when the updated app reconciles its named store.
        settings.application.denyAppInstallation = nil
        settings.dateAndTime.requireAutomaticDateAndTime = true
    }
}
