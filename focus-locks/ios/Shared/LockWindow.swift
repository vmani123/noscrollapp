import Foundation

struct BlockDuration {
    var hours = 1
    var minutes = 0
    var seconds = 0

    var timeInterval: TimeInterval? {
        guard (0...168).contains(hours), (0...59).contains(minutes), (0...59).contains(seconds) else {
            return nil
        }
        let total = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        guard total >= LockWindow.minimumDuration, total <= LockWindow.maximumDuration else { return nil }
        return total
    }

    var summary: String { "\(hours)h \(minutes)m \(seconds)s" }
}

struct LockWindow: Codable, Equatable {
    static let maximumDuration: TimeInterval = 7 * 24 * 60 * 60
    static let minimumDuration: TimeInterval = 1
    static let minimumMonitoringDuration: TimeInterval = 15 * 60
    let start: Date
    let end: Date

    init(start: Date, end: Date) throws {
        let duration = end.timeIntervalSince(start)
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              duration >= Self.minimumDuration, duration <= Self.maximumDuration else {
            throw WindowError.invalidDuration
        }
        self.start = start
        self.end = end
    }

    func isActive(at date: Date) -> Bool { start <= date && date < end }
    func isCommitted(at date: Date) -> Bool { date < end }

    // Device Activity requires a 15-minute monitoring interval. For shorter
    // blocks its end warning reconciles at the real expiry; the stored window
    // still controls when restrictions apply, independently of monitor length.
    var monitoringEnd: Date { max(end, start.addingTimeInterval(Self.minimumMonitoringDuration)) }
    var expiryWarning: DateComponents? {
        let seconds = Int(monitoringEnd.timeIntervalSince(end))
        guard seconds > 0 else { return nil }
        return DateComponents(minute: seconds / 60, second: seconds % 60)
    }

    private enum CodingKeys: String, CodingKey { case start, end }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(start: container.decode(Date.self, forKey: .start),
                      end: container.decode(Date.self, forKey: .end))
    }

    enum WindowError: LocalizedError {
        case invalidDuration
        var errorDescription: String? { "A block must last between 1 second and 7 days." }
    }
}
