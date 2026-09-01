import Foundation
import Testing
@testable import Glow

/// The worked states of `docs/week-marks.md` §4.3, as fixtures (#347).
///
/// The spec draws the model in seven pictures; these are those pictures, so a
/// change that moves one of them has to say which and why rather than quietly
/// redrawing the document's own examples. §4.3 has already earned this: walking
/// its figures and asserting the marks summed to seven caught a rejected-credit
/// example that drew two marks on a 5x row.
///
/// Read `[○][·  ·]` as `open:0-0 inactive:1-2` — the shape helper below is the
/// same notation the suites in `WeekSpansTests` use.
@Suite("The spec's worked states")
struct MarkFixtureTests {
    private let calendar = TestCalendar.monday
    /// The week beginning Monday 2026-08-17.
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }

    private func shape(target: Int, done: [Int] = [], today: Int) -> String {
        let week = week
        return WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { week.days[$0] })
            ),
            in: week, today: week.days[today], target: target,
            editing: .todayOnly, restDay: nil, calendar: calendar
        ).map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }.joined(separator: " ")
    }

    /// §4.3, "Week start, nothing logged". The remainder-right division, and
    /// the open mark ending at today.
    @Test("Monday, nothing logged: singles first and the slack at the weekend")
    func weekStart() {
        #expect(shape(target: 7, today: 0)
            == "open:0-0 inactive:1-1 inactive:2-2 inactive:3-3 inactive:4-4 inactive:5-5 inactive:6-6")
        #expect(shape(target: 6, today: 0)
            == "open:0-0 inactive:1-1 inactive:2-2 inactive:3-3 inactive:4-4 inactive:5-6")
        #expect(shape(target: 5, today: 0)
            == "open:0-0 inactive:1-1 inactive:2-2 inactive:3-4 inactive:5-6")
        #expect(shape(target: 4, today: 0) == "open:0-0 inactive:1-2 inactive:3-4 inactive:5-6")
        #expect(shape(target: 3, today: 0) == "open:0-0 inactive:1-3 inactive:4-6")
        #expect(shape(target: 2, today: 0) == "open:0-0 inactive:1-6")
        // Even the final open rep stops at today; the future is not a control.
        #expect(shape(target: 1, today: 0) == "open:0-0")
    }

    /// §4.3, "Monday logged, still Monday". Today is spent, so no row has an
    /// open mark and what follows the completion is arithmetic that divides.
    @Test("Monday logged on Monday: nothing is left open")
    func mondayLoggedOnMonday() {
        #expect(shape(target: 7, done: [0], today: 0)
            == "filled:0-0 inactive:1-1 inactive:2-2 inactive:3-3 inactive:4-4 inactive:5-5 inactive:6-6")
        #expect(shape(target: 5, done: [0], today: 0)
            == "filled:0-0 inactive:1-1 inactive:2-2 inactive:3-4 inactive:5-6")
        #expect(shape(target: 3, done: [0], today: 0) == "filled:0-0 inactive:1-3 inactive:4-6")
        #expect(shape(target: 1, done: [0], today: 0) == "filled:0-6")
    }

    /// §4.3, "Mon done, Tuesday skipped, Wed done — Wednesday, spent".
    ///
    /// Tuesday is swallowed by Wednesday's mark on every row that can still
    /// afford it. Only 7x, where every rep owns a day, has an unavoidable miss
    /// — and the ✕ lands on Tuesday, between the two completions, which is the
    /// case that forces the mark list to interleave by day rather than run all
    /// the completions before all the lost reps.
    @Test("A skipped Tuesday is swallowed by Wednesday, except at seven a week")
    func skippedTuesday() {
        #expect(shape(target: 7, done: [0, 2], today: 2)
            == "filled:0-0 missed:1-1 filled:2-2 inactive:3-3 inactive:4-4 inactive:5-5 inactive:6-6")
        #expect(shape(target: 6, done: [0, 2], today: 2)
            == "filled:0-0 filled:1-2 inactive:3-3 inactive:4-4 inactive:5-5 inactive:6-6")
        #expect(shape(target: 5, done: [0, 2], today: 2)
            == "filled:0-0 filled:1-2 inactive:3-3 inactive:4-4 inactive:5-6")
        #expect(shape(target: 4, done: [0, 2], today: 2)
            == "filled:0-0 filled:1-2 inactive:3-4 inactive:5-6")
        #expect(shape(target: 3, done: [0, 2], today: 2) == "filled:0-0 filled:1-2 inactive:3-6")
        // Met: the last mark runs to the end.
        #expect(shape(target: 2, done: [0, 2], today: 2) == "filled:0-0 filled:1-6")
    }

    /// #476: the last rep still reaches back over blank days, but its open
    /// drawing stops at today like every other open rep.
    @Test("The last rep owed stops at today")
    func oneRepOwedOnSaturday() {
        #expect(shape(target: 3, done: [0, 1], today: 5) == "filled:0-0 filled:1-1 open:2-5")
    }

    /// §4.3, "3x, only Monday done, Saturday". Two owed, two days: Saturday and
    /// Sunday are both now mandatory. The open mark still reaches back, but
    /// Sunday keeps its column.
    @Test("Two owed against two days: Sunday keeps its column")
    func twoOwedOnSaturday() {
        #expect(shape(target: 3, done: [0], today: 5) == "filled:0-0 open:1-5 inactive:6-6")
    }

    /// #476: a lost rep is one day, on the first day it could have happened;
    /// the next open rep absorbs the unused days after it.
    @Test("The ✕ is one day and the open rep absorbs what follows")
    func oneDeadRepOnThursday() {
        #expect(shape(target: 5, today: 3)
            == "missed:0-0 open:1-3 inactive:4-4 inactive:5-5 inactive:6-6")
    }

    /// Saturday's lost rep is Monday's one-day cross; the live rep owns the
    /// claimable run from Tuesday through Saturday.
    @Test("A blank three-a-week Saturday starts with one cross")
    func blankWeekBreaksOnFriday() {
        #expect(shape(target: 3, today: 5) == "missed:0-0 open:1-5 inactive:6-6")
    }
}

/// **`Frequency.daily` and the span model must agree** (#347).
///
/// A seven-a-week row is day-pinned through `WeekGrid`, not `WeekSpans`, so the
/// two never meet in the app. They are the same claim about the same week all
/// the same: at `target == 7` every rep owns a column, and the §5 rule fires on
/// any blank past day — which is exactly `WeekGrid`'s per-day miss. If they ever
/// disagree, one of them is wrong, and nothing else in the suite would say so.
///
/// **With no rest day.** A stored legacy rest day deliberately uses the older
/// divider, while #476 changes the shipping seven-day path only. Narrowing the
/// sweep is that feature boundary written down; widen it when the separately
/// scoped rest-day return is designed and built.
@Suite("Seven a week is the daily row")
struct DailyAgreementTests {
    private let calendar = TestCalendar.monday
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }

    @Test("At seven a week the marks are the daily row's slots, column for column")
    func sevenAWeekMatchesTheDailyRow() {
        let week = week
        for restColumn in [nil] as [Int?] {
            let restDay = restColumn.map { TestPreferences.weekday(ofColumn: $0, in: week) }
            for todayColumn in 0...6 {
                for pattern in 0..<128 {
                    let done = (0...6).filter {
                        pattern & (1 << $0) != 0 && $0 <= todayColumn && $0 != restColumn
                    }
                    guard done == (0...6).filter({ pattern & (1 << $0) != 0 }) else { continue }
                    let days = Set(done.map { week.days[$0] })

                    let slots = WeekGrid.slots(
                        for: .fixture(frequency: .daily, completedDays: days),
                        in: week, today: week.days[todayColumn],
                        editing: .todayOnly, restDay: restDay, calendar: calendar
                    )
                    let marks = WeekSpans.spans(
                        for: .fixture(frequency: .timesPerWeek(7), completedDays: days),
                        in: week, today: week.days[todayColumn], target: 7,
                        editing: .todayOnly, restDay: restDay, calendar: calendar
                    )
                    let what = "today \(todayColumn), done \(done), "
                        + "rest \(String(describing: restColumn))"

                    // Seven marks, one column each: the spans *are* the columns.
                    #expect(marks.count == 7, "mark count — \(what)")
                    #expect(marks.allSatisfy { $0.dayCount == 1 }, "a mark spans two days — \(what)")

                    // The rest day is the one state the two spell differently:
                    // `WeekGrid` has a `.rest` case and a span cannot be in it,
                    // because a span covers a run of days rather than one (#73).
                    // Everywhere else they must say the same word.
                    for column in 0...6 where slots[column].state != .rest {
                        let detail = "column \(column): span \(marks[column].state.rawValue) "
                            + "vs slot \(slots[column].state.rawValue) — \(what)"
                        #expect(marks[column].state == slots[column].state, "\(detail)")
                    }
                }
            }
        }
    }
}
