import Foundation

public enum MondayTrigger: String, Codable, CaseIterable, Sendable {
    case manual, midnight, morning, firstActivity
}

public struct MondaySchedule: Sendable {
    public var trigger: MondayTrigger
    public var completedDays: Set<String>

    public init(trigger: MondayTrigger = .manual, completedDays: Set<String> = []) {
        self.trigger = trigger
        self.completedDays = completedDays
    }

    public func occurrence(at date: Date, timeZone: TimeZone, mouseMoved: Bool) -> String? {
        guard trigger != .manual else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour], from: date)
        guard parts.weekday == 2 else { return nil }
        if trigger == .morning && (parts.hour ?? 0) < 9 { return nil }
        if trigger == .firstActivity && !mouseMoved { return nil }
        let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return completedDays.contains(key) ? nil : key
    }
}
