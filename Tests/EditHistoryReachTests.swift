import Foundation
import Testing
@testable import Glow

@Suite("Edit History reach")
struct EditHistoryReachTests {
    @Test("The past is the record or twelve weeks, and the future is exactly twelve")
    func asymmetricReach() throws {
        var calendar = WeekCalendar.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 2
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3
        )))
        let current = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        let oldRecord = try #require(calendar.date(
            byAdding: .day, value: -7 * 40, to: current
        ))
        let reach = EditHistoryReach.from(
            recordStart: oldRecord, today: today, calendar: calendar
        )

        #expect(reach.earliest == oldRecord)
        #expect(reach.latest == calendar.date(
            byAdding: .day, value: 7 * EditHistoryReach.futureWeeks, to: current
        ))
    }

    @Test("No record still reaches twelve weeks in both directions")
    func emptyRecord() throws {
        var calendar = WeekCalendar.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        calendar.firstWeekday = 2
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 29
        )))
        let current = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        let reach = EditHistoryReach.from(
            recordStart: nil, today: today, calendar: calendar
        )

        #expect(reach.earliest == calendar.date(byAdding: .day, value: -84, to: current))
        #expect(reach.latest == calendar.date(byAdding: .day, value: 84, to: current))
    }

    @Test("Stepping clamps at both ends across a daylight-saving change")
    func clampedSteps() throws {
        var calendar = WeekCalendar.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Havana"))
        calendar.firstWeekday = 2
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5
        )))
        let reach = EditHistoryReach.from(
            recordStart: nil, today: today, calendar: calendar
        )

        #expect(reach.step(reach.earliest, by: -1, calendar: calendar) == reach.earliest)
        #expect(reach.step(reach.latest, by: 1, calendar: calendar) == reach.latest)
        let next = reach.step(reach.earliest, by: 1, calendar: calendar)
        #expect(next > reach.earliest)
        #expect(WeekCalendar.startOfWeek(containing: next, calendar: calendar) == next)
    }
}
