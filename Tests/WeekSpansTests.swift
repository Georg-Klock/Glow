import Foundation
import Testing
@testable import Glow

/// The span rule was inferred from three examples in the design file rather
/// than specified. These three tests are those examples, so if the inference is
/// wrong there is one obvious place to correct it.
@Suite("Week spans")
struct WeekSpansTests {
    private let calendar = TestCalendar.monday
    /// Friday of the week beginning Monday 2026-08-17.
    private let friday = TestCalendar.date(2026, 8, 21)
    private var week: Week { WeekCalendar.week(containing: friday, calendar: calendar) }

    /// No rest day, said out loud. These are the design file's own examples and
    /// they are read against a plain week; a rest day arriving from elsewhere
    /// would move the boundaries they exist to pin (#105).
    private func spans(_ habit: HabitSnapshot, target: Int, today: Date? = nil) -> [SlotSpan] {
        TestPreferences.withWeek(restDay: nil) {
            WeekSpans.spans(
                for: habit,
                in: week,
                today: today ?? friday,
                target: target,
                editing: .todayOnly, calendar: calendar
            )
        }
    }

    @Test("Two a week, nothing done: the open span runs to today and the rest waits")
    func openSpanEndsAtToday() {
        let row = spans(.fixture(frequency: .timesPerWeek(2)), target: 2)

        #expect(row.count == 2)
        #expect(row[0].state == .open)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 4)  // Monday through Friday
        #expect(row[1].state == .inactive)
        #expect(row[1].firstDay == 5 && row[1].lastDay == 6)  // the weekend
    }

    @Test("Two a week, one done earlier: the open span runs from today to the end")
    func openSpanStartsAtToday() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [TestCalendar.date(2026, 8, 18)]  // Tuesday
        )
        let row = spans(habit, target: 2)

        #expect(row.count == 2)
        #expect(row[0].state == .filled)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 3)  // Monday through Thursday
        #expect(row[1].state == .open)
        #expect(row[1].firstDay == 4 && row[1].lastDay == 6)  // Friday through Sunday
    }

    @Test("Once the goal is met the week stops being divided at all")
    func goalMetIsOneSpan() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(1),
            completedDays: [TestCalendar.date(2026, 8, 18)]
        )
        let row = spans(habit, target: 1)

        #expect(row.count == 1)
        #expect(row[0].state == .filled)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 6)
    }

    // MARK: - The edges the design file did not show

    @Test("The open span always contains today", arguments: 0...6)
    func openSpanContainsToday(dayIndex: Int) {
        let today = week.days[dayIndex]
        for target in 2...6 {
            let row = spans(.fixture(frequency: .timesPerWeek(target)), target: target, today: today)
            guard let open = row.first(where: { $0.state == .open }) else { continue }
            #expect(
                open.firstDay <= dayIndex && dayIndex <= open.lastDay,
                "\(target)x on day \(dayIndex): open span is \(open.firstDay)...\(open.lastDay)"
            )
        }
    }

    @Test("A completion logged today closes the row: nothing is left open")
    func doneTodayLeavesNothingOpen() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3),
            completedDays: [friday]
        )
        let row = spans(habit, target: 3)

        #expect(!row.contains { $0.state == .open })
        // Today's completion is the one a tap undoes.
        #expect(row.filter(\.isTappable).count == 1)
        #expect(row.first(where: \.isTappable)?.state == .filled)
    }

    @Test("Spans tile the week exactly, whatever the day and the target")
    func spansTileTheWeek() {
        // The row is drawn as an HStack of span widths; a gap or an overlap in
        // the day ranges would put every column out of line with the daily rows.
        for dayIndex in 0...6 {
            let today = week.days[dayIndex]
            for target in 2...6 {
                for doneCount in 0...target {
                    let done = Set(week.days.prefix(doneCount))
                    let habit = HabitSnapshot.fixture(
                        frequency: .timesPerWeek(target),
                        completedDays: done
                    )
                    let row = spans(habit, target: target, today: today)
                    guard !row.isEmpty else { continue }

                    #expect(row.first?.firstDay == 0)
                    #expect(row.last?.lastDay == 6)
                    for (a, b) in zip(row, row.dropFirst()) {
                        let detail = "target \(target), day \(dayIndex), done \(doneCount): "
                            + "\(a.firstDay)...\(a.lastDay) then \(b.firstDay)...\(b.lastDay)"
                        #expect(b.firstDay == a.lastDay + 1, "\(detail)")
                    }
                }
            }
        }
    }

    @Test("More completions than the goal do not overflow the row")
    func extraCompletionsClamp() {
        // A habit edited from 5x down to 2x keeps its completions.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: Set(week.days.prefix(5))
        )
        let row = spans(habit, target: 2)

        #expect(row.count == 1)
        #expect(row[0].lastDay == 6)
    }
}

/// #81: a weekly row draws exactly `target` spans, however late in the week it
/// is. The suite above is the design file's examples; this one is the rule that
/// covers the days the file did not draw.
@Suite("Week spans, late in the week", .serialized)
struct LateWeekSpansTests {
    private let calendar = TestCalendar.monday
    /// The week beginning Monday 2026-08-17.
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }
    private func day(_ column: Int) -> Date { week.days[column] }

    /// One implementation, in `TestSupport`. See `TestPreferences`.
    private func withRest(_ column: Int?, _ body: () throws -> Void) rethrows {
        try TestPreferences.withWeek(
            restDay: column.map { TestPreferences.weekday(ofColumn: $0, in: week) },
            body
        )
    }

    /// `.todayOnly` unless a test says otherwise: the design file's examples and
    /// the arithmetic tables are read against the widget's rule, which is what
    /// every surface's rule used to be (#116).
    private func row(
        target: Int, done: [Int] = [], todayColumn: Int, editing: SlotEditing = .todayOnly
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week,
            today: day(todayColumn),
            target: target,
            editing: editing, calendar: calendar
        )
    }

    /// Compact shorthand for a row: one `state:first-last` per span.
    private func shape(_ spans: [SlotSpan]) -> String {
        spans.map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }.joined(separator: " ")
    }

    // MARK: - The issue's tables

    @Test("Nothing logged, no rest day: the squeeze arrives on the last days")
    func blankWeekTable() {
        #expect(shape(row(target: 2, todayColumn: 5)) == "open:0-5 inactive:6-6")
        #expect(shape(row(target: 2, todayColumn: 6)) == "missed:0-0 open:1-6")
        #expect(shape(row(target: 3, todayColumn: 5)) == "missed:0-0 open:1-5 inactive:6-6")
        #expect(shape(row(target: 3, todayColumn: 6)) == "missed:0-0 missed:1-1 open:2-6")
    }

    @Test("The completed block yields once something is lost")
    func completedBlockYields() {
        // Three a week, one logged on Monday, and it is Sunday. Two reps are
        // owed against one day: the done block gives up the columns the lost
        // rep and the open one need, which it never did before #81.
        #expect(shape(row(target: 3, done: [0], todayColumn: 6))
            == "filled:0-4 missed:5-5 open:6-6")
    }

    @Test("A rest day brings the squeeze forward a day")
    func restDayTable() {
        withRest(6) {
            #expect(shape(row(target: 2, todayColumn: 4)) == "open:0-4 inactive:5-6")
            #expect(shape(row(target: 2, todayColumn: 5)) == "missed:0-0 open:1-6")
        }
    }

    @Test("A week already over spends its last columns on what was not done")
    func finishedWeek() {
        // Looking back at a week from a later one. Two a week, one logged:
        // one bar and one span for the rep that never happened, rather than
        // two half-week bars.
        let later = TestCalendar.date(2026, 8, 26)
        let spans = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2), completedDays: [day(0)]),
            in: week, today: later, target: 2, editing: .todayOnly, calendar: calendar
        )
        #expect(shape(spans) == "filled:0-5 missed:6-6")
    }

    @Test("A week that has not started divides evenly")
    func futureWeek() {
        let earlier = TestCalendar.date(2026, 8, 10)
        let spans = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2)),
            in: week, today: earlier, target: 2, editing: .todayOnly, calendar: calendar
        )
        #expect(shape(spans) == "inactive:0-3 inactive:4-6")
    }

    // MARK: - The invariants, swept

    @Test("Every row draws exactly its target, contiguous, covering all seven")
    func invariantsHold() {
        for rest in [nil, 0, 2, 5, 6] as [Int?] {
            withRest(rest) {
                for target in 1...6 {
                    for todayColumn in 0...6 {
                        for doneCount in 0..<target {
                            // Completions on the earliest days, one per day,
                            // and never on a day that could not carry one.
                            let done = Array(0..<doneCount).filter { $0 <= todayColumn }
                            guard done.count == doneCount else { continue }
                            let spans = row(
                                target: target, done: done, todayColumn: todayColumn
                            )
                            let what = "target \(target), today \(todayColumn), done \(doneCount), rest \(String(describing: rest)): \(shape(spans))"

                            #expect(spans.count == target, "span count — \(what)")
                            #expect(spans.allSatisfy { $0.dayCount >= 1 }, "empty span — \(what)")
                            #expect(spans.first?.firstDay == 0, "starts at 0 — \(what)")
                            #expect(spans.last?.lastDay == 6, "ends at 6 — \(what)")
                            for (a, b) in zip(spans, spans.dropFirst()) {
                                #expect(b.firstDay == a.lastDay + 1, "gap — \(what)")
                            }
                            // At most one open span, and it contains today.
                            let open = spans.filter { $0.state == .open }
                            #expect(open.count <= 1, "two open — \(what)")
                            if let only = open.first {
                                #expect(
                                    only.firstDay <= todayColumn && todayColumn <= only.lastDay,
                                    "open span does not contain today — \(what)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The X arrives only once the miss is unavoidable (#82)

    @Test("Two a week, blank: clean through Saturday, one cross on Sunday")
    func theCrossArrivesOnTheLastDay() {
        // The strict inequality, stated as a row. On Saturday two reps are
        // owed against two live days and the week is still winnable; on Sunday
        // it is not. The mock draws the X a day earlier than this; the rule
        // stands and the row moves.
        for todayColumn in 0...5 {
            let spans = row(target: 2, todayColumn: todayColumn)
            #expect(!spans.contains { $0.state == .missed },
                    "crossed on column \(todayColumn), which is still winnable")
        }
        #expect(row(target: 2, todayColumn: 6).count { $0.state == .missed } == 1)
    }

    @Test("A rest day brings the cross forward a day too")
    func theCrossFollowsTheRestDay() {
        withRest(6) {
            for todayColumn in 0...4 {
                #expect(!row(target: 2, todayColumn: todayColumn).contains { $0.state == .missed },
                        "crossed on column \(todayColumn)")
            }
            #expect(row(target: 2, todayColumn: 5).count { $0.state == .missed } == 1)
        }
    }

    @Test("Three a week on the last day: two crosses and one open, in that order")
    func twoCrossesAndAnOpen() {
        let spans = row(target: 3, todayColumn: 6)
        #expect(spans.map(\.state) == [.missed, .missed, .open])
    }

    @Test("A cross is inert, and the row stays live around it")
    func crossesAreInertButTheRowIsNot() {
        let spans = row(target: 3, todayColumn: 6)
        #expect(spans.filter { $0.state == .missed }.allSatisfy { !$0.isTappable })
        // A partially lost week is not a finished one: what is still reachable
        // still glows and is still worth logging.
        #expect(spans.count { $0.isTappable } == 1)
        #expect(spans.first { $0.isTappable }?.state == .open)
    }

    @Test("A finished week crosses every rep it never got to")
    func finishedWeekCrossesTheRest() {
        let later = TestCalendar.date(2026, 8, 26)
        for (target, done) in [(2, 0), (2, 1), (3, 1), (6, 4)] {
            let spans = WeekSpans.spans(
                for: .fixture(
                    frequency: .timesPerWeek(target),
                    completedDays: Set((0..<done).map { day($0) })
                ),
                in: week, today: later, target: target, editing: .todayOnly, calendar: calendar
            )
            #expect(spans.count { $0.state == .missed } == target - done,
                    "target \(target), done \(done): \(shape(spans))")
        }
    }

    @Test("A met goal is never crossed, on any day of the week")
    func metGoalIsNeverCrossed() {
        for todayColumn in 0...6 {
            let spans = row(target: 2, done: [0, 1], todayColumn: todayColumn)
            #expect(!spans.contains { $0.state == .missed },
                    "met goal crossed on column \(todayColumn)")
        }
    }

    @Test("A cross reads as missed")
    func crossHasAVoice() {
        // `SlotSpan.mark` stopped folding a miss into a socket, which is what
        // makes it draw the ✕ — and `SpanView` reads it out to match.
        let spans = row(target: 3, todayColumn: 6)
        #expect(spans.first { $0.state == .missed }?.mark == .missed)
        #expect(spans.first { $0.state == .inactive }?.mark == nil)
    }

    // MARK: - No span is exactly the rest column (#100)

    /// True when the rest day's window covers a span from end to end, so
    /// nothing of it is drawn.
    private func isSwallowed(_ span: SlotSpan, restColumn: Int) -> Bool {
        let track: CGFloat = 194
        guard let window = RestWindow.inSpan(
            firstDay: span.firstDay, lastDay: span.lastDay,
            restIndex: restColumn, trackWidth: track
        ) else { return false }
        let width = SlotLayout.spanWidth(trackWidth: track, dayCount: span.dayCount)
        return window.lowerBound <= 0 && window.upperBound >= width
    }

    /// Every row this suite can build, as `(rest, target, today, done)`.
    private func everyRow(_ check: (Int, [SlotSpan], String) -> Void) {
        for restColumn in 0...6 {
            withRest(restColumn) {
                for target in 1...6 {
                    for todayColumn in 0...6 {
                        for doneCount in 0..<target where doneCount <= todayColumn {
                            let done = Array(0..<doneCount)
                            let spans = row(
                                target: target, done: done, todayColumn: todayColumn
                            )
                            let what = "rest \(restColumn), target \(target), today \(todayColumn), done \(doneCount): \(shape(spans))"
                            check(restColumn, spans, what)
                        }
                    }
                }
            }
        }
    }

    @Test("A lost rep never occupies the rest column alone")
    func noSpanIsSwallowedWhole() {
        // The bug: a one-column span *on* the rest column has its whole extent
        // subtracted by `RestWindow`, so the ✕ was drawn and invisible and the
        // row showed one fewer mark than its goal. 6x/week on Sunday with
        // Wednesday resting drew four crosses for five lost reps.
        //
        // **Only `.missed`.** A `.filled` or `.inactive` span draws as
        // structure — the same unlit line either way, since #47 — and structure
        // vanishing in the rest column is not a loss, it is #72: that column
        // draws nothing at all. A ✕ is the one span-mark that is a *claim*, and
        // a claim silently not drawn is the thing being ruled out. This sweep
        // records 78 swallowed structural spans and no crosses, which is the
        // shape the two rules together should produce.
        everyRow { restColumn, spans, what in
            for span in spans
            where span.state == .missed && isSwallowed(span, restColumn: restColumn) {
                Issue.record("a cross vanishes — \(what)")
            }
        }
    }

    @Test("The seven columns are still covered, with a rest day anywhere")
    func coverageSurvivesTheStraddle() {
        everyRow { _, spans, what in
            #expect(spans.first?.firstDay == 0, "starts at 0 — \(what)")
            #expect(spans.last?.lastDay == 6, "ends at 6 — \(what)")
            for (a, b) in zip(spans, spans.dropFirst()) {
                #expect(b.firstDay == a.lastDay + 1, "gap — \(what)")
            }
        }
    }

    @Test("The row that reported it draws five crosses, not four")
    func theReportedRow() {
        var spans: [SlotSpan] = []
        withRest(2) { spans = row(target: 6, todayColumn: 6) }
        let drawn = shape(spans)
        let crosses = spans.filter { $0.state == .missed }.count
        #expect(crosses == 5, "\(drawn)")
        // The one that used to sit on the rest column now takes the next
        // column with it, so it has somewhere to be seen.
        let onRest = spans.first { $0.firstDay <= 2 && $0.lastDay >= 2 }
        #expect(onRest?.dayCount == 2, "\(drawn)")
    }

    @Test("Nothing is tappable on the rest day, and the open span is otherwise")
    func tappability() {
        withRest(3) {
            // Today is the rest day: the middle span keeps its geometry and
            // asks for nothing.
            let resting = row(target: 3, todayColumn: 3)
            #expect(!resting.contains { $0.state == .open })
            #expect(resting.allSatisfy { !$0.isTappable })
            #expect(resting.count == 3)

            // The day after, it asks again.
            let live = row(target: 3, todayColumn: 4)
            #expect(live.count(where: { $0.isTappable }) == 1)
            #expect(live.first { $0.isTappable }?.state == .open)
        }
    }
    @Test("The division does not change with the surface, only the actions do")
    func surfaceDoesNotMoveTheGeometry() {
        // The whole safety of #116: `SlotEditing` is a pass over the finished
        // row, so a week divides the same way on both surfaces and only the
        // days the spans carry differ.
        for target in 1...6 {
            for todayColumn in 0...6 {
                let widget = row(target: target, done: [0], todayColumn: todayColumn)
                let app = row(
                    target: target, done: [0], todayColumn: todayColumn,
                    editing: .week(allowingFuture: false)
                )
                #expect(shape(widget) == shape(app), "\(target)x on column \(todayColumn)")
            }
        }
    }

    @Test("In the week view a span carries the last day it may write")
    func spansCarryTheirLastWritableDay() {
        // Sunday, three a week, nothing logged: two reps have run out of days
        // and the third is open. On the widget only the open span acts.
        let widget = row(target: 3, todayColumn: 6)
        #expect(shape(widget) == "missed:0-0 missed:1-1 open:2-6")
        #expect(widget.map(\.actionDay) == [nil, nil, day(6)])

        // In the app every span covers a day that can still be corrected, so
        // every span acts — the ✕ included. A rep logged late is a rep that
        // happened, and the arithmetic then stops calling it lost.
        let app = row(target: 3, todayColumn: 6, editing: .week(allowingFuture: false))
        #expect(app.map(\.actionDay) == [day(0), day(1), day(6)])
    }

    @Test("A span entirely ahead of today acts only with the demo in")
    func futureSpansWaitForTheDemo() {
        // Friday, two a week: the open span runs to today and the weekend span
        // is entirely in the future.
        #expect(shape(row(target: 2, todayColumn: 4)) == "open:0-4 inactive:5-6")

        let plain = row(target: 2, todayColumn: 4, editing: .week(allowingFuture: false))
        #expect(plain.map(\.actionDay) == [day(4), nil])

        let demo = row(target: 2, todayColumn: 4, editing: .week(allowingFuture: true))
        #expect(demo.map(\.actionDay) == [day(4), day(6)])
    }

    // MARK: - An earlier week (#117)

    /// A day two weeks after the week under test, so the week is over and the
    /// `todayIndex == nil` branch is the one doing the work.
    private var later: Date { TestCalendar.date(2026, 8, 31) }

    private func pastRow(
        target: Int, done: [Int] = [], editing: SlotEditing = .week(allowingFuture: false)
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week, today: later, target: target, editing: editing, calendar: calendar
        )
    }

    @Test("A finished week still draws exactly its target, and every span acts")
    func pastWeekInvariantsHold() {
        for rest in [nil, 0, 3, 6] as [Int?] {
            withRest(rest) {
                for target in 1...6 {
                    for doneCount in 0...target {
                        let done = Array(0..<doneCount)
                        let spans = pastRow(target: target, done: done)
                        let what = "target \(target), done \(doneCount), rest \(String(describing: rest)): \(shape(spans))"

                        // A met goal is one span across the whole week; short of
                        // it, exactly `target`. The current week's rule, and it
                        // does not change because the week is over.
                        #expect(
                            spans.count == (doneCount >= target ? 1 : target),
                            "span count — \(what)"
                        )
                        #expect(spans.first?.firstDay == 0, "starts at 0 — \(what)")
                        #expect(spans.last?.lastDay == 6, "ends at 6 — \(what)")
                        for (a, b) in zip(spans, spans.dropFirst()) {
                            #expect(b.firstDay == a.lastDay + 1, "gap — \(what)")
                        }
                        // R1: a week that is over has nothing open in it.
                        #expect(!spans.contains { $0.state == .open }, "open — \(what)")

                        for span in spans {
                            let writable = (span.firstDay...span.lastDay).filter {
                                !WeekPreferences.isRestDay(week.days[$0], calendar: calendar)
                            }
                            guard let action = span.actionDay else {
                                // The only span with nothing to write is one
                                // covering the rest day and nothing else.
                                #expect(writable.isEmpty, "no action — \(what)")
                                continue
                            }
                            // The day a span hands out is a day it covers, and
                            // never the day nothing can happen on.
                            #expect(week.index(of: action).map(writable.contains) == true,
                                    "action outside the span — \(what)")
                        }
                    }
                }
            }
        }
    }

    @Test("The rest day is refused in an earlier week too")
    func theRestDayHoldsInThePast() {
        withRest(3) {
            #expect(pastRow(target: 2).allSatisfy { $0.actionDay != day(3) })
            #expect(pastRow(target: 4, done: [0, 1]).allSatisfy { $0.actionDay != day(3) })
        }
    }

    @Test("The widget cannot reach into an earlier week")
    func todayOnlyActsNowhereInThePast() {
        for target in 1...6 {
            let spans = pastRow(target: target, done: [0], editing: .todayOnly)
            #expect(spans.allSatisfy { !$0.isTappable }, "\(target)x")
        }
    }

    @Test("Logging a day the week had given up on takes a cross away")
    func aLateCompletionUnmakesACross() {
        // Three a week, one logged: two reps ran out of days, so two crosses.
        let before = pastRow(target: 3, done: [0])
        #expect(shape(before) == "filled:0-4 missed:5-5 missed:6-6")
        #expect(before.count { $0.state == .missed } == 2)

        // Correct the record — the tap the pager exists for — and the
        // arithmetic re-runs: the rep happened, late, so it is no longer lost.
        let after = pastRow(target: 3, done: [0, 2])
        #expect(after.count { $0.state == .missed } == 1)
        #expect(after.count == 3)

        // And filling it out entirely stops the week being divided at all.
        let met = pastRow(target: 3, done: [0, 2, 4])
        #expect(shape(met) == "filled:0-6")
    }

    @Test("The division of a finished week does not change with the surface")
    func pastWeekGeometryIsTheSameOnBothSurfaces() {
        for target in 1...6 {
            for doneCount in 0...target {
                let done = Array(0..<doneCount)
                #expect(
                    shape(pastRow(target: target, done: done, editing: .todayOnly))
                        == shape(pastRow(target: target, done: done)),
                    "\(target)x, \(doneCount) done"
                )
            }
        }
    }

    @Test("A span never carries the rest day, whatever the surface")
    func spansNeverCarryTheRestDay() {
        withRest(6) {
            // Sunday rests, so the span covering the weekend hands out Saturday
            // rather than the day nothing can happen on.
            let demo = row(target: 2, todayColumn: 4, editing: .week(allowingFuture: true))
            #expect(shape(demo) == "open:0-4 inactive:5-6")
            #expect(demo.map(\.actionDay) == [day(4), day(5)])
        }

        withRest(0) {
            // Monday rests and is in the past: the app reaches back past it.
            let app = row(target: 3, todayColumn: 6, editing: .week(allowingFuture: false))
            for span in app {
                #expect(span.actionDay != day(0))
            }
        }
    }

}

/// #47: the spans say how much, the dots say when.
@Suite("Week dots", .serialized)
struct WeekDotsTests {
    private let calendar = TestCalendar.monday
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }
    private func day(_ column: Int) -> Date { week.days[column] }

    /// One implementation, in `TestSupport`. See `TestPreferences`.
    private func withRest(_ column: Int?, _ body: () throws -> Void) rethrows {
        try TestPreferences.withWeek(
            restDay: column.map { TestPreferences.weekday(ofColumn: $0, in: week) },
            body
        )
    }

    private func columns(_ frequency: Frequency, done: [Int]) -> [Int] {
        WeekDots.columns(
            for: .fixture(frequency: frequency, completedDays: Set(done.map { day($0) })),
            in: week,
            calendar: calendar
        )
    }

    @Test("A dot on every weekday a completion actually landed on")
    func dotsAreDayPinned() {
        #expect(columns(.timesPerWeek(3), done: [1, 5]) == [1, 5])
        #expect(columns(.timesPerWeek(3), done: []) == [])
        // Order is the week's, not the order they were logged in.
        #expect(columns(.timesPerWeek(3), done: [5, 0, 2]) == [0, 2, 5])
    }

    @Test("A completion past the goal still lights its day")
    func completionsPastTheGoalCount() {
        // Four on a three-a-week habit: the fourth has a day even though it has
        // no span. `WeekDots` never reads the target, which is what makes this
        // fall out rather than need a case.
        #expect(columns(.timesPerWeek(3), done: [0, 1, 2, 3]) == [0, 1, 2, 3])
    }

    @Test("The rest day is never lit, even holding a completion")
    func restDayIsNotLit() {
        // Not this type's opinion: #72 settled that the rest column draws
        // nothing at all, a stored completion included. It still counts
        // everywhere it counted; a dot would be drawing it.
        withRest(2) {
            #expect(columns(.timesPerWeek(3), done: [1, 2, 5]) == [1, 5])
        }
    }

    @Test("Daily habits and blank rows have no dots of their own")
    func onlySpanRows() {
        // A daily row is already seven day-pinned columns and already puts the
        // light on the day; a per-day habit has no week row at all.
        #expect(WeekDots.columns(
            for: .fixture(frequency: .timesPerDay(3), completedDays: [day(1)]),
            in: week, calendar: calendar
        ).isEmpty)
        #expect(WeekDots.columns(
            for: .fixture(isSpacer: true), in: week, calendar: calendar
        ).isEmpty)
    }

    @Test("The dots say which days, once")
    func dotsHaveAVoice() {
        // One element for the run, not one per dot: the days are a single
        // fact, and a row already has up to six span elements. See #104.
        let habit = HabitSnapshot.fixture(
            name: "Workout",
            frequency: .timesPerWeek(3),
            completedDays: [day(1), day(4)]
        )
        #expect(
            WeekDots.spokenDays(for: habit, in: week, calendar: calendar)
                == "logged Tuesday and Friday"
        )
    }

    @Test("A row with nothing lit says nothing at all")
    func silentWhenUnlit() {
        // nil rather than an empty string, so the view can drop the element
        // instead of adding a stop that speaks nothing.
        #expect(WeekDots.spokenDays(
            for: .fixture(frequency: .timesPerWeek(3)), in: week, calendar: calendar
        ) == nil)
        // And the two rows that have no dots at all keep their silence.
        #expect(WeekDots.spokenDays(
            for: .fixture(frequency: .timesPerDay(3), completedDays: [day(1)]),
            in: week, calendar: calendar
        ) == nil)
    }

    @Test("What is not drawn is not spoken")
    func restDayIsNotSpoken() {
        // The rest column draws nothing (#72), so it says nothing — otherwise
        // VoiceOver would report a day the screen does not show.
        withRest(2) {
            let habit = HabitSnapshot.fixture(
                frequency: .timesPerWeek(3), completedDays: [day(1), day(2), day(4)]
            )
            #expect(
                WeekDots.spokenDays(for: habit, in: week, calendar: calendar)
                    == "logged Tuesday and Friday"
            )
        }
    }

    @Test("One day is a day, not a list of one")
    func singleDay() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3), completedDays: [day(0)]
        )
        #expect(
            WeekDots.spokenDays(for: habit, in: week, calendar: calendar)
                == "logged Monday"
        )
    }

    @Test("Three days keep their separators")
    func threeDays() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3), completedDays: [day(0), day(2), day(6)]
        )
        #expect(
            WeekDots.spokenDays(for: habit, in: week, calendar: calendar)
                == "logged Monday, Wednesday and Sunday"
        )
    }

    @Test("Completions outside the week are not this week's dots")
    func onlyThisWeek() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3),
            completedDays: [TestCalendar.date(2026, 8, 10), day(1)]
        )
        #expect(WeekDots.columns(for: habit, in: week, calendar: calendar) == [1])
    }

    @Test("An achieved span draws the same line as one still to come")
    func achievedSpansAreStructure() {
        // The other half of #47. A met goal and an untouched week are the same
        // marks, and the dots are what tell them apart.
        let met = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2), completedDays: [day(0), day(1)]),
            in: week, today: day(4), target: 2, editing: .todayOnly, calendar: calendar
        )
        #expect(met.allSatisfy { $0.mark == .upcoming })
        // And the two that are still marks keep their own.
        let partial = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2)),
            in: week, today: day(6), target: 2, editing: .todayOnly, calendar: calendar
        )
        #expect(partial.map(\.mark) == [.missed, .openToday])
    }
}
