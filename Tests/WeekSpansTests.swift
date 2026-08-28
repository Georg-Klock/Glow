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

    /// No rest day, said out loud — and since #181 said *in the call*, so no
    /// rest day can arrive from elsewhere and move the boundaries these exist
    /// to pin (#105). These are the design file's own examples.
    private func spans(_ habit: HabitSnapshot, target: Int, today: Date? = nil) -> [SlotSpan] {
        WeekSpans.spans(
            for: habit,
            in: week,
            today: today ?? friday,
            target: target,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
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

    @Test("Two a week, one done earlier: the completion keeps its day, the open mark takes the rest")
    func openSpanStartsAtToday() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [TestCalendar.date(2026, 8, 18)]  // Tuesday
        )
        let row = spans(habit, target: 2)

        // The completion anchors on Tuesday and reaches back over Monday
        // (#339); it used to be handed the whole block before today, which put
        // its edge on Thursday — a day nothing happened on. The open mark is
        // the last in the row, so it runs to the end of the week.
        #expect(row.count == 2)
        #expect(row[0].state == .filled)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 1)  // Monday and Tuesday
        #expect(row[1].state == .open)
        #expect(row[1].firstDay == 2 && row[1].lastDay == 6)  // Wednesday through Sunday
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

        // Two marks for a 2x row, whatever the record holds. The first two
        // completions keep their days; the three past the target have no mark
        // of their own and fall inside the last one, which runs to the end
        // (#342). A 2x row logged five times looks like a 2x row logged twice.
        #expect(row.count == 2)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 0)
        #expect(row[1].firstDay == 1 && row[1].lastDay == 6)
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

    /// One column of this week as a rest day, handed to the body to pass on.
    ///
    /// It used to pin `WeekPreferences.restDay` around the body and let the
    /// rows pick it up out of the store. Since #181 the rest day is an argument
    /// to `WeekSpans`, so this only converts a column to a weekday — nothing is
    /// set, and nothing can leak into another suite (#105, #168).
    private func withRest(_ column: Int?, _ body: (Int?) throws -> Void) rethrows {
        try body(column.map { TestPreferences.weekday(ofColumn: $0, in: week) })
    }

    /// `.todayOnly` unless a test says otherwise: the design file's examples and
    /// the arithmetic tables are read against the widget's rule, which is what
    /// every surface's rule used to be (#116). No rest day unless one is named.
    private func row(
        target: Int, done: [Int] = [], todayColumn: Int,
        editing: SlotEditing = .todayOnly, restDay: Int? = nil
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week,
            today: day(todayColumn),
            target: target,
            editing: editing, restDay: restDay, calendar: calendar
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
        // The ✕ lands on the day the week broke on, and the mark carrying it
        // reaches back over the blank days before it (#341). It used to be
        // parked immediately left of the open span, on a day it had nothing to
        // do with.
        #expect(shape(row(target: 2, todayColumn: 6)) == "missed:0-5 open:6-6")
        #expect(shape(row(target: 3, todayColumn: 5)) == "missed:0-4 open:5-5 inactive:6-6")
        #expect(shape(row(target: 3, todayColumn: 6)) == "missed:0-4 missed:5-5 open:6-6")
    }

    @Test("A completion keeps its day, and the rep that died keeps Saturday")
    func completedBlockYields() {
        // Three a week, one logged on Monday, and it is Sunday. Two reps are
        // owed against one day, so one is gone — and it went on Saturday, the
        // day after which the goal became unreachable. Monday's mark is one
        // column because Monday is where it happened; the dead rep swallows
        // Tuesday through Saturday (#339, #341).
        #expect(shape(row(target: 3, done: [0], todayColumn: 6))
            == "filled:0-0 missed:1-5 open:6-6")
    }

    @Test("A rest day brings the squeeze forward a day")
    func restDayTable() {
        withRest(6) { rest in
            #expect(shape(row(target: 2, todayColumn: 4, restDay: rest)) == "open:0-4 inactive:5-6")
            #expect(shape(row(target: 2, todayColumn: 5, restDay: rest)) == "missed:0-4 open:5-6")
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
            in: week, today: later, target: 2,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        // Monday's completion is one column, and the rep that never happened
        // takes the rest of the week: a week that is over has no open mark to
        // hold the slack, so the last mark holds it.
        #expect(shape(spans) == "filled:0-0 missed:1-6")
    }

    @Test("A week that has not started divides evenly")
    func futureWeek() {
        let earlier = TestCalendar.date(2026, 8, 10)
        let spans = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2)),
            in: week, today: earlier, target: 2,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        // Remainder to the right (#340): three columns then four, not four
        // then three.
        #expect(shape(spans) == "inactive:0-2 inactive:3-6")
    }

    // MARK: - The invariants, swept

    @Test("Every row draws exactly its target, contiguous, covering all seven")
    func invariantsHold() {
        for rest in [nil, 0, 2, 5, 6] as [Int?] {
            withRest(rest) { restDay in
                for target in 1...6 {
                    for todayColumn in 0...6 {
                        for doneCount in 0..<target {
                            // Completions on the earliest days, one per day,
                            // and never on a day that could not carry one.
                            let done = Array(0..<doneCount).filter { $0 <= todayColumn }
                            guard done.count == doneCount else { continue }
                            let spans = row(
                                target: target, done: done,
                                todayColumn: todayColumn, restDay: restDay
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
        withRest(6) { rest in
            for todayColumn in 0...4 {
                #expect(
                    !row(target: 2, todayColumn: todayColumn, restDay: rest)
                        .contains { $0.state == .missed },
                    "crossed on column \(todayColumn)"
                )
            }
            #expect(
                row(target: 2, todayColumn: 5, restDay: rest).count { $0.state == .missed } == 1
            )
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
                in: week, today: later, target: target,
                editing: .todayOnly, restDay: nil, calendar: calendar
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
            withRest(restColumn) { restDay in
                for target in 1...6 {
                    for todayColumn in 0...6 {
                        for doneCount in 0..<target where doneCount <= todayColumn {
                            let done = Array(0..<doneCount)
                            let spans = row(
                                target: target, done: done,
                                todayColumn: todayColumn, restDay: restDay
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
        withRest(2) { rest in spans = row(target: 6, todayColumn: 6, restDay: rest) }
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
        withRest(3) { rest in
            // Today is the rest day: the middle span keeps its geometry and
            // asks for nothing.
            let resting = row(target: 3, todayColumn: 3, restDay: rest)
            #expect(!resting.contains { $0.state == .open })
            #expect(resting.allSatisfy { !$0.isTappable })
            #expect(resting.count == 3)

            // The day after, it asks again.
            let live = row(target: 3, todayColumn: 4, restDay: rest)
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
        #expect(shape(widget) == "missed:0-4 missed:5-5 open:6-6")
        #expect(widget.map(\.actionDay) == [nil, nil, day(6)])

        // In the app every span covers a day that can still be corrected, so
        // every span acts — the ✕ included. A rep logged late is a rep that
        // happened, and the arithmetic then stops calling it lost.
        let app = row(target: 3, todayColumn: 6, editing: .week(allowingFuture: false))
        #expect(app.map(\.actionDay) == [day(4), day(5), day(6)])
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

    // MARK: - Undoing a span lands on a day that was logged (#256)

    /// The week surface, so `withColumnActions` is the code under test.
    private func weekRow(
        target: Int, done: [Int], today: Date? = nil, restDay: Int? = nil
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week, today: today ?? day(4), target: target,
            editing: .week(allowingFuture: false), restDay: restDay, calendar: calendar
        )
    }

    /// **A filled span may only hand out a day it can actually undo** (#256).
    ///
    /// `HabitStore.toggleCompletion` is a per-day toggle: on a day carrying no
    /// completion it *adds* one. So a filled span whose `actionDay` is a day
    /// with nothing logged does not un-complete anything when it is activated —
    /// it logs a new day. On a row whose goal is already met that is invisible
    /// in the spans, because `done` is clamped to `target` and the week stays
    /// undivided; the only trace is a new dot.
    ///
    /// That is the whole of the report in #256, which read as "un-completing
    /// mostly does not register". It registers exactly when the finger lands on
    /// one of the columns that carries a dot, and those are the minority of the
    /// bar. Worse, every miss adds a completion, so the next correct tap has one
    /// more to remove before the row can drop below its target — the failure
    /// compounds.
    @Test("A filled span's action day is a day it can undo")
    func filledSpansUndoADayThatWasLogged() {
        // One a week, logged on Tuesday, today is Friday: goal met, one span
        // across the whole week. The last column this surface may write is
        // Friday — and Friday has nothing on it.
        let row = weekRow(target: 1, done: [1])
        #expect(row.count == 1)
        #expect(row[0].state == .filled)
        #expect(row[0].actionDay == day(1), "a filled span offered a day with no completion on it")
    }

    /// The same rule swept: every filled span, at every target, hands out a day
    /// that carries a completion — or hands out nothing.
    @Test("No filled span anywhere offers a day with nothing logged on it")
    func filledSpansNeverOfferAnEmptyDay() {
        for rest in [nil, 3] as [Int?] {
            withRest(rest) { restDay in
                for target in 1...6 {
                    for doneCount in 1...target {
                        let done = Array(0..<doneCount)
                        let logged = Set(done.map { day($0) })
                        for todayColumn in 0...6 {
                            let spans = weekRow(
                                target: target, done: done,
                                today: week.days[todayColumn], restDay: restDay
                            )
                            for span in spans where span.state == .filled {
                                guard let action = span.actionDay else { continue }
                                #expect(
                                    logged.contains(action),
                                    """
                                    target \(target), done \(doneCount), today \(todayColumn), \
                                    rest \(String(describing: rest)): filled span \
                                    \(span.firstDay)...\(span.lastDay) offers a day with \
                                    nothing logged on it
                                    """
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// An open span is untouched by the rule: it exists to *take* a completion,
    /// so the day under the finger is exactly right whether or not anything is
    /// logged there.
    @Test("An open span still offers its own last writable day")
    func openSpansAreUnchanged() {
        // Two a week, nothing done, today Friday: the open span is Monday
        // through Friday and its action is Friday, which has no completion on
        // it and should not need one.
        let row = weekRow(target: 2, done: [])
        let open = row.first { $0.state == .open }
        #expect(open?.actionDay == day(4))
    }

    // MARK: - An earlier week (#117)

    /// A day two weeks after the week under test, so the week is over and the
    /// `todayIndex == nil` branch is the one doing the work.
    private var later: Date { TestCalendar.date(2026, 8, 31) }

    private func pastRow(
        target: Int, done: [Int] = [], editing: SlotEditing = .week(allowingFuture: false),
        restDay: Int? = nil
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week, today: later, target: target,
            editing: editing, restDay: restDay, calendar: calendar
        )
    }

    @Test("A finished week still draws exactly its target, and every span acts")
    func pastWeekInvariantsHold() {
        for rest in [nil, 0, 3, 6] as [Int?] {
            withRest(rest) { restDay in
                for target in 1...6 {
                    for doneCount in 0...target {
                        let done = Array(0..<doneCount)
                        let spans = pastRow(target: target, done: done, restDay: restDay)
                        let what = "target \(target), done \(doneCount), rest \(String(describing: rest)): \(shape(spans))"

                        // Exactly `target` marks, met or not (#342). A met
                        // goal used to collapse to one span across the whole
                        // week, which forgot every day it had just recorded.
                        #expect(spans.count == target, "span count — \(what)")
                        #expect(spans.first?.firstDay == 0, "starts at 0 — \(what)")
                        #expect(spans.last?.lastDay == 6, "ends at 6 — \(what)")
                        for (a, b) in zip(spans, spans.dropFirst()) {
                            #expect(b.firstDay == a.lastDay + 1, "gap — \(what)")
                        }
                        // R1: a week that is over has nothing open in it.
                        #expect(!spans.contains { $0.state == .open }, "open — \(what)")

                        for span in spans {
                            let writable = (span.firstDay...span.lastDay).filter {
                                !WeekPreferences.isRestDay(
                                    week.days[$0], restDay: restDay, calendar: calendar
                                )
                            }
                            guard let action = span.actionDay else {
                                // **Two spans have nothing to write, not one.**
                                // The first covers the rest day and nothing
                                // else. The second is #256: a filled span is an
                                // undo, so it may only offer a day that carries
                                // a completion, and a filled span can cover
                                // columns none of them landed on — spans say
                                // how much, dots say when (#47). Toggling a day
                                // with nothing on it would *log* one, which is
                                // what this invariant used to require.
                                let logged = writable.filter { done.contains($0) }
                                #expect(
                                    writable.isEmpty
                                        || (span.state == .filled && logged.isEmpty),
                                    "no action — \(what)"
                                )
                                continue
                            }
                            // A filled span hands out a day it can undo.
                            if span.state == .filled {
                                #expect(
                                    week.index(of: action).map(done.contains) == true,
                                    "filled span offers an unlogged day — \(what)"
                                )
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
        withRest(3) { rest in
            #expect(pastRow(target: 2, restDay: rest).allSatisfy { $0.actionDay != day(3) })
            #expect(
                pastRow(target: 4, done: [0, 1], restDay: rest)
                    .allSatisfy { $0.actionDay != day(3) }
            )
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
        #expect(shape(before) == "filled:0-0 missed:1-5 missed:6-6")
        #expect(before.count { $0.state == .missed } == 2)

        // Correct the record — the tap the pager exists for — and the
        // arithmetic re-runs: the rep happened, late, so it is no longer lost.
        let after = pastRow(target: 3, done: [0, 2])
        #expect(after.count { $0.state == .missed } == 1)
        #expect(after.count == 3)

        // And filling it out entirely stops the week being divided at all.
        let met = pastRow(target: 3, done: [0, 2, 4])
        #expect(shape(met) == "filled:0-0 filled:1-2 filled:3-6")
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
        withRest(6) { rest in
            // Sunday rests, so the span covering the weekend hands out Saturday
            // rather than the day nothing can happen on.
            let demo = row(
                target: 2, todayColumn: 4,
                editing: .week(allowingFuture: true), restDay: rest
            )
            #expect(shape(demo) == "open:0-4 inactive:5-6")
            #expect(demo.map(\.actionDay) == [day(4), day(5)])
        }

        withRest(0) { rest in
            // Monday rests and is in the past: the app reaches back past it.
            let app = row(
                target: 3, todayColumn: 6,
                editing: .week(allowingFuture: false), restDay: rest
            )
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

    /// One column of this week as a rest day, handed to the body to pass on.
    /// See the note on `LateWeekSpansTests.withRest` and #181.
    private func withRest(_ column: Int?, _ body: (Int?) throws -> Void) rethrows {
        try body(column.map { TestPreferences.weekday(ofColumn: $0, in: week) })
    }

    private func columns(
        _ frequency: Frequency, done: [Int], restDay: Int? = nil
    ) -> [Int] {
        WeekDots.columns(
            for: .fixture(frequency: frequency, completedDays: Set(done.map { day($0) })),
            in: week,
            restDay: restDay,
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
        withRest(2) { rest in
            #expect(columns(.timesPerWeek(3), done: [1, 2, 5], restDay: rest) == [1, 5])
        }
    }

    @Test("Blank rows have no dots of their own")
    func onlySpanRows() {
        // A daily row is already seven day-pinned columns and already puts the
        // light on the day. A blank row has nothing to put light on at all.
        #expect(WeekDots.columns(
            for: .fixture(isSpacer: true), in: week, restDay: nil, calendar: calendar
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
            WeekDots.spokenDays(for: habit, in: week, restDay: nil, calendar: calendar)
                == "logged Tuesday and Friday"
        )
    }

    @Test("A row with nothing lit says nothing at all")
    func silentWhenUnlit() {
        // nil rather than an empty string, so the view can drop the element
        // instead of adding a stop that speaks nothing.
        #expect(WeekDots.spokenDays(
            for: .fixture(frequency: .timesPerWeek(3)), in: week,
            restDay: nil, calendar: calendar
        ) == nil)
        // And the row that has no dots at all keeps its silence.
        #expect(WeekDots.spokenDays(
            for: .fixture(completedDays: [day(1)], isSpacer: true),
            in: week, restDay: nil, calendar: calendar
        ) == nil)
    }

    @Test("What is not drawn is not spoken")
    func restDayIsNotSpoken() {
        // The rest column draws nothing (#72), so it says nothing — otherwise
        // VoiceOver would report a day the screen does not show.
        withRest(2) { rest in
            let habit = HabitSnapshot.fixture(
                frequency: .timesPerWeek(3), completedDays: [day(1), day(2), day(4)]
            )
            #expect(
                WeekDots.spokenDays(for: habit, in: week, restDay: rest, calendar: calendar)
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
            WeekDots.spokenDays(for: habit, in: week, restDay: nil, calendar: calendar)
                == "logged Monday"
        )
    }

    @Test("Three days keep their separators")
    func threeDays() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3), completedDays: [day(0), day(2), day(6)]
        )
        #expect(
            WeekDots.spokenDays(for: habit, in: week, restDay: nil, calendar: calendar)
                == "logged Monday, Wednesday and Sunday"
        )
    }

    @Test("Completions outside the week are not this week's dots")
    func onlyThisWeek() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3),
            completedDays: [TestCalendar.date(2026, 8, 10), day(1)]
        )
        #expect(
            WeekDots.columns(for: habit, in: week, restDay: nil, calendar: calendar) == [1]
        )
    }

    @Test("An achieved span draws the same line as one still to come")
    func achievedSpansAreStructure() {
        // The other half of #47. A met goal and an untouched week are the same
        // marks, and the dots are what tell them apart.
        let met = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2), completedDays: [day(0), day(1)]),
            in: week, today: day(4), target: 2,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(met.allSatisfy { $0.mark == .upcoming })
        // And the two that are still marks keep their own.
        let partial = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2)),
            in: week, today: day(6), target: 2,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(partial.map(\.mark) == [.missed, .openToday])
    }
}

/// #196: what makes two spans the same span across a re-render.
///
/// `SpanView` owns the mid-flight size of a completion animation as `@State`,
/// and `ForEach` decides whether that state carries over from one render to the
/// next by asking `id`. A span used to answer with its index, which `divided()`
/// reassigns freely — the span at index 2 before a tap and the one at index 2
/// after it can cover different days — so an animation could be inherited by a
/// span that was never part of it.
///
/// Both halves are asserted here, because the fix is a trade and only one half
/// is obvious. A span whose *range* changed must be a new identity, or the
/// stale animation carries over. A span whose *state* changed must keep its
/// identity, or `SpanView.onChange(of: span.state)` never runs and the
/// completion stops animating at all — which is what putting the state into the
/// identity, as the issue proposed, would have done.
@Suite("Span identity")
struct SpanIdentityTests {
    private let calendar = TestCalendar.monday
    /// The week beginning Monday 2026-08-17.
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }
    private func day(_ column: Int) -> Date { week.days[column] }

    /// A row on a surface that edits the whole week (#116), which is where a
    /// redivision can be provoked by a tap on a day that is not today.
    private func row(target: Int, done: [Int] = [], todayColumn: Int) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week, today: day(todayColumn), target: target,
            editing: .week(allowingFuture: false), restDay: nil, calendar: calendar
        )
    }

    private func shape(_ spans: [SlotSpan]) -> String {
        spans.map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }.joined(separator: " ")
    }

    @Test("A span that keeps its range keeps its identity through a completion")
    func completionKeepsIdentity() {
        // Wednesday, three a week, nothing logged: the open span runs Monday to
        // today. Logging today turns exactly that span filled without moving
        // either end of it, which is the transition `SpanView` animates.
        let before = row(target: 3, todayColumn: 2)
        let after = row(target: 3, done: [2], todayColumn: 2)
        #expect(shape(before) == "open:0-2 inactive:3-4 inactive:5-6")
        #expect(shape(after) == "filled:0-2 inactive:3-4 inactive:5-6")

        #expect(before[0].state != after[0].state)
        #expect(
            before[0].id == after[0].id,
            "the completing span must stay the same view, or it never animates"
        )
    }

    @Test("A span that is redivided is a different span")
    func redivisionChangesIdentity() {
        // Same Wednesday, today already logged, and now Monday is logged too —
        // a tap on a past day, which #116 allows and #117 allows in any week on
        // the pager. The completed block narrows from three columns to two and
        // stays `filled`, so nothing about the *state* changed: this is exactly
        // the case an index-shaped identity called "the same span" and handed a
        // running animation to.
        let before = row(target: 3, done: [2], todayColumn: 2)
        let after = row(target: 3, done: [0, 2], todayColumn: 2)
        #expect(shape(before) == "filled:0-2 inactive:3-4 inactive:5-6")
        #expect(shape(after) == "filled:0-0 filled:1-2 inactive:3-6")

        #expect(before[0].state == after[0].state)
        #expect(
            before[0].id != after[0].id,
            "a narrower span at the same index must not inherit the old one's animation"
        )
        // And nothing else in the new row may collide with it either — the
        // stale state has to have nowhere to land.
        #expect(!after.contains { $0.id == before[0].id })
    }

    @Test("No two spans in a row ever share an identity")
    func identitiesAreUniqueWithinARow() {
        for target in 1...7 {
            for todayColumn in 0...6 {
                let sets: [[Int]] = [[], [0], [0, 1], [0, 1, 2], [todayColumn], [0, todayColumn]]
                for done in sets {
                    let spans = row(
                        target: target, done: Array(Set(done)).sorted(), todayColumn: todayColumn
                    )
                    #expect(
                        Set(spans.map(\.id)).count == spans.count,
                        "\(target)x, today \(todayColumn), done \(done): \(shape(spans))"
                    )
                }
            }
        }
    }

    @Test("Identity is the range and nothing else")
    func identityIsTheRange() {
        // A row redrawn for a reason that has nothing to do with it — the habit
        // was renamed, the store republished — has to come back as itself, or
        // every re-render would cancel a running animation.
        let a = row(target: 3, done: [0], todayColumn: 4)
        let b = row(target: 3, done: [0], todayColumn: 4)
        #expect(a.map(\.id) == b.map(\.id))

        // Two spans covering the same columns are the same division whatever
        // else differs about them, which is the property the `@State` reuse
        // actually needs: same shape in the same place, same view.
        let open = SlotSpan(index: 0, firstDay: 1, lastDay: 3, state: .open, actionDay: nil)
        let filled = SlotSpan(index: 2, firstDay: 1, lastDay: 3, state: .filled, actionDay: day(1))
        #expect(open.id == filled.id)
        #expect(open.id != SlotSpan(
            index: 0, firstDay: 1, lastDay: 4, state: .open, actionDay: nil
        ).id)
    }
}

/// The invariants of `docs/week-marks.md` §3, checked rather than trusted
/// (#347).
///
/// The suites above sweep contiguous completions from Monday, which is the
/// shape a habit that is going well makes. This one sweeps **every** pattern —
/// all 128 subsets of the week — because the mark model's whole subject is the
/// blank day in the middle, and a prefix never contains one.
///
/// Every property here is stated from the fixture's own inputs rather than from
/// anything `WeekSpans` computes. That is the point: the ✕ count in particular
/// is the §5 monotonicity claim, and a test that asked `WeekSpans` what it
/// thought `lost` was would agree with it by construction.
@Suite("Mark invariants")
struct MarkInvariantsTests {
    private let calendar = TestCalendar.monday
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }

    /// One row of the sweep: what went in, and what came out.
    private struct Row {
        let target: Int
        let todayColumn: Int
        let done: [Int]
        let restColumn: Int?
        let spans: [SlotSpan]
        let what: String
    }

    /// Every `(target, today, completion pattern, rest day)` this suite covers.
    private func everyRow(_ check: (Row) -> Void) {
        let week = week
        for restColumn in [nil, 3] as [Int?] {
            let restDay = restColumn.map { TestPreferences.weekday(ofColumn: $0, in: week) }
            for target in 1...6 {
                for todayColumn in 0...6 {
                    for pattern in 0..<128 {
                        // A completion can only sit on a day that has arrived,
                        // and never on the rest day: the store refuses that
                        // write, so a row holding one is not a state the app
                        // can reach.
                        let done = (0...6).filter {
                            pattern & (1 << $0) != 0 && $0 <= todayColumn && $0 != restColumn
                        }
                        guard done == (0...6).filter({ pattern & (1 << $0) != 0 }) else { continue }
                        let spans = WeekSpans.spans(
                            for: .fixture(
                                frequency: .timesPerWeek(target),
                                completedDays: Set(done.map { week.days[$0] })
                            ),
                            in: week, today: week.days[todayColumn], target: target,
                            editing: .week(allowingFuture: false), restDay: restDay, calendar: calendar
                        )
                        check(Row(
                            target: target, todayColumn: todayColumn, done: done,
                            restColumn: restColumn, spans: spans,
                            what: "target \(target), today \(todayColumn), done \(done), "
                                + "rest \(String(describing: restColumn)): "
                                + spans.map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }
                                    .joined(separator: " ")
                        ))
                    }
                }
            }
        }
    }

    @Test("A row draws exactly its target, however the week is going")
    func exactlyTargetMarks() {
        everyRow { row in
            #expect(row.spans.count == row.target, "mark count — \(row.what)")
        }
    }

    @Test("The marks tile all seven columns, contiguous and non-overlapping")
    func marksTileTheWeek() {
        everyRow { row in
            #expect(row.spans.first?.firstDay == 0, "starts at 0 — \(row.what)")
            #expect(row.spans.last?.lastDay == 6, "ends at 6 — \(row.what)")
            #expect(row.spans.allSatisfy { $0.dayCount >= 1 }, "empty mark — \(row.what)")
            for (a, b) in zip(row.spans, row.spans.dropFirst()) {
                #expect(b.firstDay == a.lastDay + 1, "gap or overlap — \(row.what)")
            }
        }
    }

    @Test("At most one mark is open, and it contains today")
    func atMostOneOpenMark() {
        everyRow { row in
            let open = row.spans.filter { $0.state == .open }
            #expect(open.count <= 1, "two open marks — \(row.what)")
            for mark in open {
                #expect(
                    mark.firstDay <= row.todayColumn && row.todayColumn <= mark.lastDay,
                    "the open mark does not contain today — \(row.what)"
                )
            }
        }
    }

    @Test("The ✕ count is exactly the reps the days ran out on")
    func crossCountMatchesTheArithmetic() {
        everyRow { row in
            // Stated from the fixture: reps still owed, against days that can
            // still carry one. An actionable day is one from today onward that
            // is not the rest day, and not today once today is spent.
            let owed = row.target - min(row.done.count, row.target)
            let spentToday = row.done.contains(row.todayColumn)
            let daysLeft = (0...6).count {
                $0 != row.restColumn
                    && (spentToday ? $0 > row.todayColumn : $0 >= row.todayColumn)
            }
            let crosses = row.spans.count { $0.state == .missed }
            #expect(crosses == max(0, owed - daysLeft), "✕ count — \(row.what)")
        }
    }

    @Test("Every completion sits under a lit mark")
    func completionsAreCovered() {
        everyRow { row in
            // The marks past the target have no mark of their own and fall
            // inside the last one, which is filled anyway — so this holds for
            // an over-shot row too.
            for column in row.done {
                let mark = row.spans.first { $0.firstDay <= column && column <= $0.lastDay }
                #expect(mark?.state == .filled, "day \(column) is not filled — \(row.what)")
            }
        }
    }

    @Test("A completion the row has room for ends its own mark")
    func completionsAnchorOnTheirDay() {
        everyRow { row in
            // Two marks do not end on their own day, and both are the model
            // rather than an exception. The **last** mark in a row always runs
            // to the end of the week, because there is nothing after it to
            // divide. And an anchor is **clamped** when the reps behind it need
            // the columns more than the record does — a late completion on a
            // row that still owes several, which is what the old completed
            // block's yielding arithmetic did and is why it is not missed.
            guard row.done.count <= row.target,
                  !row.spans.contains(where: { $0.state == .missed }),
                  row.done.last.map({ $0 + row.target - row.done.count <= 6 }) ?? true
            else { return }
            let filled = row.spans.enumerated().filter { $0.element.state == .filled }
            for (position, mark) in filled.enumerated() where mark.offset < row.spans.count - 1 {
                #expect(
                    mark.element.lastDay == row.done[position],
                    "mark \(position) does not end on its day — \(row.what)"
                )
            }
        }
    }
}
