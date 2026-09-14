import Foundation
import Testing
@testable import MondayCore

@Test(arguments: [MondayTrigger.sunday2345, .sunday2350, .sunday2359, .randomSunday])
func automaticPlaybackOnlyOccursInTheSundayWindow(trigger: MondayTrigger) throws {
    let zone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let schedule = MondaySchedule(trigger: trigger, randomSecond: 450)
    #expect(schedule.occurrence(at: try date("2026-09-13T23:44:59+09:00"), timeZone: zone) == nil)
    #expect(schedule.occurrence(at: try date("2026-09-13T23:59:59+09:00"), timeZone: zone) == "2026-09-13")
    for value in ["2026-09-14T00:00:00+09:00", "2026-09-14T09:00:00+09:00", "2026-09-12T23:59:59+09:00"] {
        #expect(schedule.occurrence(at: try date(value), timeZone: zone) == nil)
    }
}

@Test(arguments: [(MondayTrigger.sunday2345, 0), (.sunday2350, 300), (.sunday2359, 840), (.randomSunday, 537)])
func fixedAndRandomTimesHaveAnExactLowerBoundary(trigger: MondayTrigger, offset: Int) throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let start = try date("2026-09-13T23:45:00Z").addingTimeInterval(Double(offset))
    let schedule = MondaySchedule(trigger: trigger, randomSecond: 537)
    #expect(schedule.occurrence(at: start.addingTimeInterval(-0.01), timeZone: zone) == nil)
    #expect(schedule.occurrence(at: start, timeZone: zone) == "2026-09-13")
}

@Test func completionAndManualPlaybackNeverRepeatAutomatically() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let sunday = try date("2026-09-13T23:59:00Z")
    #expect(MondaySchedule().occurrence(at: sunday, timeZone: zone) == nil)
    let schedule = MondaySchedule(trigger: .sunday2345, completedDays: ["2026-09-13"])
    #expect(schedule.occurrence(at: sunday, timeZone: zone) == nil)
    #expect(schedule.occurrence(at: try date("2026-09-20T23:59:00Z"), timeZone: zone) == "2026-09-20")
}

@Test func schedulingUsesLocalCivilTimeAcrossDSTAndTimeZones() throws {
    let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let schedule = MondaySchedule(trigger: .sunday2350)
    for value in ["2026-03-08T23:50:00-07:00", "2026-11-01T23:50:00-08:00"] {
        let instant = try date(value)
        #expect(schedule.occurrence(at: instant, timeZone: la) != nil)
        #expect(schedule.occurrence(at: instant, timeZone: tokyo) == nil)
    }
}

@Test func schedulerSleepsUntilSundayInsteadOfPollingAllWeek() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let monday = try date("2026-09-14T00:00:00Z")
    #expect(MondaySchedule.nextCheck(after: monday, timeZone: zone) == (try date("2026-09-20T23:45:00Z")))
    let sunday = try date("2026-09-13T23:59:59.500Z")
    #expect(MondaySchedule.nextCheck(after: sunday, timeZone: zone) == monday)
}

private func date(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    if value.contains(".500") { formatter.formatOptions.insert(.withFractionalSeconds) }
    return try #require(formatter.date(from: value))
}
