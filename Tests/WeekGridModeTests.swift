import Foundation
import Testing
@testable import Glow

/// #557: This Week is one view in three modes, and the one pager consults the
/// reach the active mode names.
@Suite("Week grid mode")
struct WeekGridModeTests {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = WeekCalendar.calendar
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        calendar.firstWeekday = 2
        return calendar
    }

    @Test("Browsing and list editing stop at the current week; correcting reaches twelve ahead")
    func reachFollowsTheMode() throws {
        let calendar = try calendar("Europe/Berlin")
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 4
        )))
        let current = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        let record = try #require(calendar.date(byAdding: .day, value: -7 * 30, to: current))

        for mode in [WeekGridMode.browsing, .editingList] {
            let reach = mode.reach(recordStart: record, today: today, calendar: calendar)
            #expect(reach.latest == current, "\(mode) pages forward past today")
            #expect(reach.earliest == record)
            #expect(reach.step(current, by: 1, calendar: calendar) == current)
        }

        let correcting = WeekGridMode.correctingHistory.reach(
            recordStart: record, today: today, calendar: calendar
        )
        #expect(correcting.earliest == record, "the past edge is the same record-or-twelve floor")
        #expect(correcting.latest == calendar.date(
            byAdding: .day, value: 7 * EditHistoryReach.futureWeeks, to: current
        ))
        #expect(correcting.step(current, by: 1, calendar: calendar) > current)
        #expect(correcting.contains(current))
    }

    @Test("Only correcting takes the list's management away")
    func management() {
        #expect(WeekGridMode.browsing.offersHabitManagement)
        #expect(WeekGridMode.editingList.offersHabitManagement)
        #expect(!WeekGridMode.correctingHistory.offersHabitManagement)
        #expect(WeekGridMode.correctingHistory.drawsFactualDays)
        #expect(!WeekGridMode.browsing.drawsFactualDays)
    }

    @Test("The distance is signed, and the title ladder mirrors forward")
    func titles() throws {
        let calendar = try calendar("America/Havana")
        // Across Cuba's midnight DST change (#242), so the day count is not a
        // clean multiple of seven in seconds.
        let today = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5
        )))
        let current = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        for offset in -13...13 {
            let moved = try #require(calendar.date(byAdding: .day, value: 7 * offset, to: current))
            let week = WeekCalendar.startOfWeek(containing: moved, calendar: calendar)
            #expect(
                WeekDistanceTitle.weeks(from: current, to: week, calendar: calendar) == offset,
                "offset \(offset)"
            )
        }

        let range = "Nov 2 – Nov 8"
        #expect(WeekDistanceTitle.title(weeks: 0, range: range) == "This Week")
        #expect(WeekDistanceTitle.subtitle(weeks: 0, range: range) == nil)
        #expect(WeekDistanceTitle.title(weeks: -1, range: range) == "Last Week")
        #expect(WeekDistanceTitle.subtitle(weeks: -1, range: range) == range)
        #expect(WeekDistanceTitle.title(weeks: -2, range: range) == "Two Weeks Ago")
        #expect(WeekDistanceTitle.title(weeks: -5, range: range) == range)
        #expect(WeekDistanceTitle.subtitle(weeks: -5, range: range) == "5 weeks ago")
        #expect(WeekDistanceTitle.title(weeks: 1, range: range) == "Next Week")
        #expect(WeekDistanceTitle.subtitle(weeks: 1, range: range) == range)
        #expect(WeekDistanceTitle.title(weeks: 2, range: range) == "Two Weeks Ahead")
        #expect(WeekDistanceTitle.title(weeks: 12, range: range) == range)
        #expect(WeekDistanceTitle.subtitle(weeks: 12, range: range) == "12 weeks ahead")
    }
}
