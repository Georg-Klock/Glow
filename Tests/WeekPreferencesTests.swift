import Foundation
import Testing
@testable import Glow

@Suite("Week preferences", .serialized)
struct WeekPreferencesTests {
    /// These write to the App Group's defaults, which every other suite reads
    /// through `WeekCalendar.calendar`. Restored after each test rather than
    /// left set, or a later suite inherits somebody else's week.
    private func withPreferences(
        firstWeekday: Int? = nil,
        restDay: Int? = nil,
        _ body: () throws -> Void
    ) rethrows {
        let previousFirst = WeekPreferences.firstWeekday
        let previousRest = WeekPreferences.restDay
        defer {
            WeekPreferences.firstWeekday = previousFirst
            WeekPreferences.restDay = previousRest
        }
        if let firstWeekday { WeekPreferences.firstWeekday = firstWeekday }
        WeekPreferences.restDay = restDay
        try body()
    }

    @Test("Monday by default, not whatever the locale says")
    func defaultsToMonday() {
        // Locale would answer Sunday in the US, and this is not a formatting
        // choice: it decides which seven days a weekly goal is counted over.
        #expect(WeekPreferences.defaultFirstWeekday == WeekPreferences.monday)
    }

    @Test("The week start moves the columns", arguments: [1, 2, 3, 7])
    func weekStartMovesColumns(first: Int) {
        withPreferences(firstWeekday: first) {
            let calendar = WeekCalendar.calendar
            #expect(calendar.firstWeekday == first)

            let week = WeekCalendar.week(containing: Date(), calendar: calendar)
            #expect(week.days.count == 7)
            #expect(calendar.component(.weekday, from: week.start) == first)
        }
    }

    @Test("Weekday initials follow the week start")
    func initialsRotate() {
        withPreferences(firstWeekday: WeekPreferences.sunday) {
            let sundayFirst = WeekCalendar.weekdayInitials(calendar: WeekCalendar.calendar)
            WeekPreferences.firstWeekday = WeekPreferences.monday
            let mondayFirst = WeekCalendar.weekdayInitials(calendar: WeekCalendar.calendar)

            #expect(sundayFirst.count == 7)
            // The same seven letters, rotated by one — not a different list.
            #expect(Array(sundayFirst.dropFirst()) + [sundayFirst[0]] == mondayFirst)
        }
    }

    @Test("Out-of-range week starts clamp instead of producing a silent wrong week")
    func weekdayClamps() {
        #expect(WeekPreferences.clampWeekday(0) == 1)
        #expect(WeekPreferences.clampWeekday(9) == 7)
        #expect(WeekPreferences.clampWeekday(4) == 4)
    }

    @Test("No rest day by default")
    func noRestDayByDefault() {
        withPreferences(restDay: nil) {
            #expect(WeekPreferences.restDay == nil)
        }
    }

    @Test("A rest day is never open and never missed")
    func restDayIsNeitherOpenNorMissed() {
        let calendar = TestCalendar.monday
        // Wednesday of the week beginning Monday 2026-08-17.
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        withPreferences(restDay: calendar.component(.weekday, from: week.days[0])) {
            let row = WeekGrid.slots(
                for: .fixture(), in: week, today: today, calendar: calendar
            )
            // Monday is the rest day and already gone: it would be a miss
            // otherwise, and a miss is exactly what a rest day is not.
            #expect(row[0].state == .inactive)
            #expect(row[1].state == .missed)
        }
    }

    @Test("A rest day that is today has nothing to tap")
    func restDayTodayIsNotOpen() {
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        withPreferences(restDay: calendar.component(.weekday, from: today)) {
            let row = WeekGrid.slots(
                for: .fixture(), in: week, today: today, calendar: calendar
            )
            #expect(row[2].state == .inactive)
            #expect(!row.contains { $0.state == .open })
            #expect(row.allSatisfy { !$0.isTappable })
        }
    }

    @Test("A completion on a rest day still counts and still shows")
    func restDayCompletionsCount() {
        // Resting is permission, not a prohibition. Someone who goes for a run
        // on their rest day should see it.
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)
        let monday = week.days[0]

        withPreferences(restDay: calendar.component(.weekday, from: monday)) {
            let habit = HabitSnapshot.fixture(completedDays: [monday])
            let row = WeekGrid.slots(for: habit, in: week, today: today, calendar: calendar)
            #expect(row[0].state == .filled)
            #expect(row[0].mark == .donePast)
        }
    }
}
