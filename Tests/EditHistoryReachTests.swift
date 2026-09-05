import Foundation
import Testing
@testable import Glow

/// #592, narrowing #543: Correct History reaches a flat four weeks either side
/// of the current week, and the record moves neither edge.
@Suite("Edit History reach")
struct EditHistoryReachTests {
    @Test("Four weeks either way, whatever the record says")
    func flatReach() throws {
        var calendar = WeekCalendar.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 2
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3
        )))
        let current = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        let reach = EditHistoryReach.from(today: today, calendar: calendar)

        #expect(EditHistoryReach.pastWeeks == 4)
        #expect(EditHistoryReach.futureWeeks == 4)
        #expect(reach.earliest == calendar.date(
            byAdding: .day, value: -7 * EditHistoryReach.pastWeeks, to: current
        ))
        #expect(reach.latest == calendar.date(
            byAdding: .day, value: 7 * EditHistoryReach.futureWeeks, to: current
        ))

        // The record used to extend the past edge through `WeekReach`; a
        // forty-week record now reaches no further than an empty one. That
        // is the cost #592 names: a completion five weeks old is outside
        // this screen's reach.
        let oldRecord = try #require(calendar.date(
            byAdding: .day, value: -7 * 40, to: current
        ))
        let browsing = WeekReach.from(
            recordStart: oldRecord, today: today, calendar: calendar
        )
        #expect(browsing.earliest == oldRecord, "browsing still reaches the record")
        #expect(reach.earliest > oldRecord, "correcting does not")
        #expect(!reach.contains(oldRecord))
    }

    @Test("Both edges are week starts across a midnight DST change")
    func edgesAreWeekStarts() throws {
        var calendar = WeekCalendar.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Havana"))
        calendar.firstWeekday = 2
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5
        )))
        let reach = EditHistoryReach.from(today: today, calendar: calendar)
        #expect(WeekCalendar.startOfWeek(containing: reach.earliest, calendar: calendar) == reach.earliest)
        #expect(WeekCalendar.startOfWeek(containing: reach.latest, calendar: calendar) == reach.latest)
        let current = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        #expect(reach.contains(current))
        #expect(reach.step(current, by: -EditHistoryReach.pastWeeks, calendar: calendar) == reach.earliest)
        #expect(reach.step(current, by: EditHistoryReach.futureWeeks, calendar: calendar) == reach.latest)
    }

    @Test("Stepping clamps at both ends across a daylight-saving change")
    func clampedSteps() throws {
        var calendar = WeekCalendar.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Havana"))
        calendar.firstWeekday = 2
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5
        )))
        let reach = EditHistoryReach.from(today: today, calendar: calendar)

        #expect(reach.step(reach.earliest, by: -1, calendar: calendar) == reach.earliest)
        #expect(reach.step(reach.latest, by: 1, calendar: calendar) == reach.latest)
        let next = reach.step(reach.earliest, by: 1, calendar: calendar)
        #expect(next > reach.earliest)
        #expect(WeekCalendar.startOfWeek(containing: next, calendar: calendar) == next)
    }
}
