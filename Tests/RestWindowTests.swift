import Foundation
import Testing
@testable import Glow

/// A span never shows in the rest day's column — and the arithmetic that
/// decides the spans is untouched by that.
@Suite("Rest window", .serialized)
struct RestWindowTests {
    /// The large widget's own track, so the numbers below are the shipping
    /// ones rather than a round number chosen to make the arithmetic tidy.
    private let track: CGFloat = 194
    private var slot: CGFloat { SlotLayout.dailySlot(trackWidth: track) }
    private var gap: CGFloat { SlotLayout.gap(trackWidth: track) }

    // MARK: - The window

    @Test("A span that does not reach the rest day loses nothing")
    func outsideTheSpan() {
        #expect(RestWindow.inSpan(
            firstDay: 0, lastDay: 3, restIndex: 6, trackWidth: track
        ) == nil)
        #expect(RestWindow.inSpan(
            firstDay: 4, lastDay: 6, restIndex: 1, trackWidth: track
        ) == nil)
    }

    @Test("No rest day set is no window")
    func noRestDay() {
        #expect(RestWindow.inSpan(
            firstDay: 0, lastDay: 6, restIndex: nil, trackWidth: track
        ) == nil)
    }

    @Test("The window is the column's slot plus the gap on each side")
    func windowIsSlotPlusBothGaps() {
        // Wednesday, in a span covering the whole week: the hole is one slot
        // wide plus a gap either side, so its edges land on Tuesday's and
        // Thursday's slot edges rather than in the middle of the air.
        let window = RestWindow.inSpan(
            firstDay: 0, lastDay: 6, restIndex: 2, trackWidth: track
        )
        let centre = 2 * (slot + gap) + slot / 2
        #expect(window?.lowerBound.isNear(centre - slot / 2 - gap) == true)
        #expect(window?.upperBound.isNear(centre + slot / 2 + gap) == true)
        // Tuesday's slot ends exactly where the window begins.
        #expect(window?.lowerBound.isNear(1 * (slot + gap) + slot) == true)
        // Thursday's slot begins exactly where the window ends.
        #expect(window?.upperBound.isNear(3 * (slot + gap)) == true)
    }

    @Test("A met goal with Sunday resting ends flush with Saturday's slot")
    func sundayRestEndsTheBar() {
        // The met-goal case from the mockup: one span across all seven
        // columns, and the bar must stop at Saturday's slot edge rather than
        // leaving a stub hanging in the last gap.
        let window = RestWindow.inSpan(
            firstDay: 0, lastDay: 6, restIndex: 6, trackWidth: track
        )
        #expect(window?.lowerBound.isNear(5 * (slot + gap) + slot) == true)
        // Past the span's right edge, deliberately — at the end of a span the
        // window is a shortening rather than a hole, and the shape clamps.
        #expect((window?.upperBound ?? 0) > track)
    }

    @Test("The rest day at a span's leading edge cuts its first column off")
    func restAtTheStart() {
        let window = RestWindow.inSpan(
            firstDay: 3, lastDay: 6, restIndex: 3, trackWidth: track
        )
        // Before the span's own leading edge — again a shortening, clamped by
        // the shape — and ending where the span's second column begins.
        #expect((window?.lowerBound ?? 0) < 0)
        #expect(window?.upperBound.isNear(slot + gap) == true)
    }

    @Test("A one-day span on the rest day is swallowed whole")
    func spanEntirelyInsideTheWindow() {
        // Reachable with a 7×/week habit and a rest day: one span, one column,
        // and that column is the rest day. It draws nothing.
        let window = RestWindow.inSpan(
            firstDay: 4, lastDay: 4, restIndex: 4, trackWidth: track
        )
        let width = SlotLayout.spanWidth(trackWidth: track, dayCount: 1)
        #expect((window?.lowerBound ?? 0) < 0)
        #expect((window?.upperBound ?? 0) > width)
    }

    // MARK: - The arithmetic is untouched

    @Test("A met goal still covers all seven columns with a rest day")
    func metGoalStillSpansTheWeek() {
        // The point of subtracting a window from the *shape* rather than
        // re-dividing six columns: `WeekSpans` does not learn about rest days
        // at all, so its packing rule and its tests are unaffected.
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [week.days[0], week.days[1]]
        )

        func spans(restDay: Int?) -> [SlotSpan] {
            WeekSpans.spans(
                for: habit, in: week, today: today, target: 2,
                editing: .todayOnly, restDay: restDay, calendar: calendar
            )
        }

        // Two marks, one per completion: a met goal keeps every completion on
        // its day and lets the last mark run to the end (#342).
        let withoutRest = spans(restDay: nil)
        #expect(withoutRest.count == 2)
        #expect(withoutRest[0].firstDay == 0 && withoutRest[0].lastDay == 0)
        #expect(withoutRest[1].firstDay == 1 && withoutRest[1].lastDay == 6)

        // Sunday resting changes nothing about the division.
        let sunday = calendar.component(.weekday, from: week.days[6])
        #expect(spans(restDay: sunday) == withoutRest)
    }
}

private extension CGFloat {
    func isNear(_ other: CGFloat, within tolerance: CGFloat = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
