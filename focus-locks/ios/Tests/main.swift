import Foundation

precondition(BlockDuration().timeInterval == 3600)
precondition(BlockDuration(hours: 1, minutes: 2, seconds: 3).timeInterval == 3723)
precondition(BlockDuration(hours: 0, minutes: 15, seconds: 1).timeInterval == 901)
precondition(BlockDuration(hours: 0, minutes: 0, seconds: 1).timeInterval == 1)
precondition(BlockDuration(hours: 0, minutes: 14, seconds: 59).timeInterval == 899)
precondition(BlockDuration(hours: 168, minutes: 0, seconds: 0).timeInterval == 604800)
for invalid in [BlockDuration(hours: 0, minutes: 0, seconds: 0),
                BlockDuration(hours: 168, minutes: 0, seconds: 1),
                BlockDuration(hours: -1, minutes: 0, seconds: 0),
                BlockDuration(hours: 1, minutes: 60, seconds: 0),
                BlockDuration(hours: 1, minutes: 0, seconds: 60)] {
    precondition(invalid.timeInterval == nil)
}

let start = Date(timeIntervalSince1970: 1_800_000_000)
let oneSecond = try LockWindow(start: start, end: start.addingTimeInterval(1))
precondition(oneSecond.isActive(at: start))
precondition(!oneSecond.isActive(at: oneSecond.end))
precondition(oneSecond.monitoringEnd.timeIntervalSince(start) == 900)
precondition(oneSecond.expiryWarning == DateComponents(minute: 14, second: 59))
precondition(oneSecond.monitoringEnd.addingTimeInterval(-899) == oneSecond.end)
let almostFifteenMinutes = try LockWindow(start: start, end: start.addingTimeInterval(899))
precondition(almostFifteenMinutes.expiryWarning == DateComponents(minute: 0, second: 1))
let fifteenMinutes = try LockWindow(start: start, end: start.addingTimeInterval(900))
precondition(fifteenMinutes.monitoringEnd == fifteenMinutes.end)
precondition(fifteenMinutes.expiryWarning == nil)
let encodedSecond = try JSONEncoder().encode(oneSecond)
let decodedSecond = try JSONDecoder().decode(LockWindow.self, from: encodedSecond)
precondition(decodedSecond == oneSecond)
let week = try LockWindow(start: start, end: start.addingTimeInterval(168 * 3600))
precondition([oneSecond, week].filter { $0.isActive(at: oneSecond.end) }.count == 1)
precondition(!week.isActive(at: start.addingTimeInterval(-1)))
precondition(week.isActive(at: start))
precondition(week.isActive(at: week.end.addingTimeInterval(-0.001)))
precondition(!week.isActive(at: week.end))
precondition(week.isCommitted(at: start.addingTimeInterval(-1)))
precondition(!week.isCommitted(at: week.end))
precondition(week.monitoringEnd == week.end && week.expiryWarning == nil)
for duration: Double in [0, -1, 0.5, 604801] {
    do {
        _ = try LockWindow(start: start, end: start.addingTimeInterval(duration))
        fatalError("Invalid duration accepted: \(duration)")
    } catch LockWindow.WindowError.invalidDuration {}
}
let encoded = try JSONEncoder().encode(week)
let decoded = try JSONDecoder().decode(LockWindow.self, from: encoded)
precondition(decoded == week)
let invalid = Data("{\"start\":0,\"end\":0.5}".utf8)
do {
    _ = try JSONDecoder().decode(LockWindow.self, from: invalid)
    fatalError("Invalid stored window accepted")
} catch LockWindow.WindowError.invalidDuration {}
let second = try LockWindow(start: start.addingTimeInterval(3600), end: week.end.addingTimeInterval(3600))
precondition([week, second].filter { $0.isActive(at: week.end) }.count == 1)
print("Duration default/conversion/validation and lock-window boundaries, maximum, overlap, persistence passed.")
