import CoreGraphics
import Foundation
import Testing
@testable import Glow

/// Which day every cadence-shaped surface may write after #543.
@Suite("Slot editing")
struct SlotEditingTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    private func day(column: Int, restDay: Int? = nil) -> Date? {
        SlotEditing.todayOnly.day(
            atColumn: column,
            in: week,
            today: today,
            restDay: restDay,
            calendar: calendar
        )
    }

    @Test("Every cadence surface reaches today and nothing else")
    func todayOnlyReachesToday() {
        #expect(day(column: 0) == nil)
        #expect(day(column: 2) == today)
        #expect(day(column: 3) == nil)
    }

    @Test("A week entirely in the past is browse-only", arguments: 0..<7)
    func pastWeekIsInert(column: Int) {
        let past = WeekCalendar.week(
            containing: TestCalendar.date(2026, 8, 3), calendar: calendar
        )
        #expect(SlotEditing.todayOnly.day(
            atColumn: column,
            in: past,
            today: today,
            restDay: nil,
            calendar: calendar
        ) == nil)
    }

    @Test("A week in the future is browse-only", arguments: 0..<7)
    func futureWeekIsInert(column: Int) {
        let future = WeekCalendar.week(
            containing: TestCalendar.date(2026, 9, 7), calendar: calendar
        )
        #expect(SlotEditing.todayOnly.day(
            atColumn: column,
            in: future,
            today: today,
            restDay: nil,
            calendar: calendar
        ) == nil)
    }

    @Test("Even today is withheld when the legacy rest setting names it")
    func restDayIsRefused() {
        let wednesday = TestPreferences.weekday(
            ofColumn: 2, in: week, calendar: calendar
        )
        #expect(day(column: 2, restDay: wednesday) == nil)
    }

    @Test("A column outside the week is not a day")
    func columnsOutsideTheWeek() {
        #expect(day(column: -1) == nil)
        #expect(day(column: 7) == nil)
    }

    @Test("A span resolves today only, and a filled span must hold today's completion")
    func spanResolution() {
        let open = SlotSpan(
            index: 0, firstDay: 0, lastDay: 4,
            state: .open, actionDay: today
        )
        let empty = HabitSnapshot.fixture(frequency: .timesPerWeek(2))
        #expect(WeekSpans.day(
            atColumn: 0, of: open, for: empty, in: week, today: today,
            editing: .todayOnly, restDay: nil, calendar: calendar
        ) == nil)
        #expect(WeekSpans.day(
            atColumn: 2, of: open, for: empty, in: week, today: today,
            editing: .todayOnly, restDay: nil, calendar: calendar
        ) == today)

        let filled = SlotSpan(
            index: 0, firstDay: 0, lastDay: 4,
            state: .filled, actionDay: nil
        )
        #expect(WeekSpans.day(
            atColumn: 2, of: filled, for: empty, in: week, today: today,
            editing: .todayOnly, restDay: nil, calendar: calendar
        ) == nil)
        let done = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2), completedDays: [today]
        )
        #expect(WeekSpans.day(
            atColumn: 2, of: filled, for: done, in: week, today: today,
            editing: .todayOnly, restDay: nil, calendar: calendar
        ) == today)
    }

    @Test("Span touch geometry remains the inverse of column placement")
    func everyColumnOfASpanResolves() {
        let track: CGFloat = 338
        for firstDay in 0..<7 {
            for column in firstDay..<7 {
                let x = SlotLayout.columnCentre(trackWidth: track, index: column)
                    - SlotLayout.columnStart(trackWidth: track, index: firstDay)
                let resolved = SlotLayout.column(
                    atX: SlotLayout.columnStart(trackWidth: track, index: firstDay) + x,
                    trackWidth: track
                )
                #expect(resolved == column, "span from \(firstDay), column \(column)")
            }
        }
    }
}
