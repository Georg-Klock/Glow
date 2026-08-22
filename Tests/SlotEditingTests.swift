import CoreGraphics
import Foundation
import Testing
@testable import Glow

/// Which days a surface may write, and which day a touch lands on.
///
/// The two halves of #116: the policy, and the geometry that resolves a finger
/// on a span into a weekday. They are tested together because a row that draws
/// a tap target it will not honour is exactly the bug the pair exists to
/// prevent.
@Suite("Slot editing")
struct SlotEditingTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    private func day(_ editing: SlotEditing, column: Int, restDay: Int? = nil) -> Date? {
        TestPreferences.withWeek(restDay: restDay) {
            editing.day(atColumn: column, in: week, today: today, calendar: calendar)
        }
    }

    // MARK: - The policy

    @Test("The widget's surface reaches today and nothing else")
    func todayOnlyReachesToday() {
        #expect(day(.todayOnly, column: 0) == nil)
        #expect(day(.todayOnly, column: 2) == today)
        #expect(day(.todayOnly, column: 3) == nil)
    }

    @Test("The week view reaches back but not forward")
    func weekReachesBack() {
        let editing = SlotEditing.week(allowingFuture: false)
        #expect(day(editing, column: 0) == TestCalendar.date(2026, 8, 17))
        #expect(day(editing, column: 2) == today)
        #expect(day(editing, column: 3) == nil)
        #expect(day(editing, column: 6) == nil)
    }

    @Test("Demo history opens the days ahead")
    func demoOpensTheFuture() {
        let editing = SlotEditing.week(allowingFuture: true)
        #expect(day(editing, column: 3) == TestCalendar.date(2026, 8, 20))
        #expect(day(editing, column: 6) == TestCalendar.date(2026, 8, 23))
    }

    @Test("No surface reaches the rest day")
    func restDayIsRefusedEverywhere() {
        // Monday, a past day the week view otherwise reaches.
        let monday = TestPreferences.weekday(ofColumn: 0, in: week, calendar: calendar)
        let cases: [SlotEditing] = [
            .todayOnly, .week(allowingFuture: false), .week(allowingFuture: true)
        ]
        for editing in cases {
            #expect(day(editing, column: 0, restDay: monday) == nil, "\(editing)")
        }

        // And when today is the rest day, today goes with it.
        let wednesday = TestPreferences.weekday(ofColumn: 2, in: week, calendar: calendar)
        for editing in cases {
            #expect(day(editing, column: 2, restDay: wednesday) == nil, "\(editing)")
        }
    }

    @Test("A column outside the week is not a day")
    func columnsOutsideTheWeek() {
        #expect(day(.week(allowingFuture: true), column: -1) == nil)
        #expect(day(.week(allowingFuture: true), column: 7) == nil)
    }

    // MARK: - Resolving a touch on a span

    @Test("A tap on a past column of a span writes that day, not today")
    func spanTapResolvesToTheColumnTouched() throws {
        // The row a 2×/week habit draws on this Wednesday with nothing logged:
        // one open span covering Monday through Wednesday, one waiting for the
        // weekend. Touching the open span over Monday has to write Monday —
        // the span's own `actionDay` is today, and that is what a location-less
        // activation falls back to.
        let track: CGFloat = 220
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(2))
        let spans = TestPreferences.withWeek(restDay: nil) {
            WeekSpans.spans(
                for: habit, in: week, today: today, target: 2,
                editing: .week(allowingFuture: false), calendar: calendar
            )
        }
        let span = try #require(spans.first { $0.state == .open })
        #expect(span.firstDay == 0)

        // A touch over Monday's column, in the span's own coordinates.
        let start = SlotLayout.columnStart(trackWidth: track, index: span.firstDay)
        let touchX = SlotLayout.columnCentre(trackWidth: track, index: 0) - start
        let column = try #require(SlotLayout.column(atX: start + touchX, trackWidth: track))

        #expect(column == 0)
        #expect(
            day(.week(allowingFuture: false), column: column) == TestCalendar.date(2026, 8, 17)
        )
        // The span itself still carries today, which is what a tap with no
        // location writes.
        #expect(span.actionDay == today)
    }

    @Test("Every column of a span resolves to its own weekday")
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
