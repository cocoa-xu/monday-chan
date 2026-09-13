import Foundation
import MondayCore
import Testing

@Test func mondayTriggersUseTheRequestedLocalTime() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let calendar = calendar(in: zone)
    let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 0)))
    let beforeMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8, minute: 59)))
    let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9)))

    #expect(MondaySchedule(trigger: .midnight).occurrence(at: midnight, timeZone: zone, mouseMoved: false) == "2026-09-14")
    #expect(MondaySchedule(trigger: .morning).occurrence(at: beforeMorning, timeZone: zone, mouseMoved: false) == nil)
    #expect(MondaySchedule(trigger: .morning).occurrence(at: morning, timeZone: zone, mouseMoved: false) == "2026-09-14")
}

@Test func firstActivityRequiresMovementAndAllTriggersDeduplicate() throws {
    let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let date = try #require(calendar(in: zone).date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 15)))
    #expect(MondaySchedule(trigger: .firstActivity).occurrence(at: date, timeZone: zone, mouseMoved: false) == nil)
    #expect(MondaySchedule(trigger: .firstActivity).occurrence(at: date, timeZone: zone, mouseMoved: true) == "2026-09-14")
    for trigger in MondayTrigger.allCases where trigger != .manual {
        #expect(MondaySchedule(trigger: trigger, completedDays: ["2026-09-14"])
            .occurrence(at: date, timeZone: zone, mouseMoved: true) == nil)
    }
}

@Test func occurrenceUsesCivilMondayInTheSuppliedTimeZone() throws {
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let instant = try #require(calendar(in: utc).date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 16)))
    #expect(MondaySchedule(trigger: .midnight).occurrence(at: instant, timeZone: utc, mouseMoved: false) == nil)
    #expect(MondaySchedule(trigger: .midnight).occurrence(at: instant, timeZone: tokyo, mouseMoved: false) == "2026-09-14")
}

private func calendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

@Test func manualAndNonMondayDatesNeverCatchUp() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let monday = try #require(calendar(in: zone).date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12)))
    let tuesday = try #require(calendar(in: zone).date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)))
    #expect(MondaySchedule(trigger: .manual).occurrence(at: monday, timeZone: zone, mouseMoved: true) == nil)
    for trigger in MondayTrigger.allCases {
        #expect(MondaySchedule(trigger: trigger).occurrence(at: tuesday, timeZone: zone, mouseMoved: true) == nil)
    }
}

@Test func completionAllowsTheNextMonday() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let nextMonday = try #require(calendar(in: zone).date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 10)))
    #expect(MondaySchedule(trigger: .morning, completedDays: ["2026-09-14"])
        .occurrence(at: nextMonday, timeZone: zone, mouseMoved: false) == "2026-09-21")
}

@Test func morningTriggerUsesCivilNineAMAcrossDaylightSavingChanges() throws {
    let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let before = try #require(calendar(in: zone).date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8, minute: 59)))
    let after = try #require(calendar(in: zone).date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9)))
    #expect(MondaySchedule(trigger: .morning).occurrence(at: before, timeZone: zone, mouseMoved: false) == nil)
    #expect(MondaySchedule(trigger: .morning).occurrence(at: after, timeZone: zone, mouseMoved: false) == "2026-11-02")
}
