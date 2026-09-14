import Foundation

public enum MondayTrigger: String, Codable, CaseIterable, Sendable {
    case manual, sunday2345, sunday2350, sunday2359, randomSunday
}

public struct MondaySchedule: Sendable {
    public struct Window: Sendable {
        public let day: String
        public let start: Date
        public let end: Date
    }

    public var trigger: MondayTrigger
    public var completedDays: Set<String>
    public var randomSecond: Int

    public init(trigger: MondayTrigger = .manual, completedDays: Set<String> = [], randomSecond: Int = 0) {
        self.trigger = trigger
        self.completedDays = completedDays
        self.randomSecond = min(max(randomSecond, 0), 899)
    }

    public static func window(on date: Date, timeZone: TimeZone) -> Window? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard parts.weekday == 1,
              let start = calendar.date(bySettingHour: 23, minute: 45, second: 0, of: date),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { return nil }
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return Window(day: day, start: start, end: end)
    }

    public func occurrence(at date: Date, timeZone: TimeZone) -> String? {
        guard trigger != .manual, let window = Self.window(on: date, timeZone: timeZone),
              !completedDays.contains(window.day), date < window.end else { return nil }
        let delay: Int
        switch trigger {
        case .manual: return nil
        case .sunday2345: delay = 0
        case .sunday2350: delay = 300
        case .sunday2359: delay = 840
        case .randomSunday: delay = randomSecond
        }
        return date >= window.start.addingTimeInterval(Double(delay)) ? window.day : nil
    }

    public static func nextCheck(after date: Date, timeZone: TimeZone) -> Date {
        if let window = window(on: date, timeZone: timeZone), date >= window.start, date < window.end {
            return min(date.addingTimeInterval(1), window.end)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.nextDate(after: date, matching: DateComponents(hour: 23, minute: 45, second: 0, weekday: 1),
                                 matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
    }
}
