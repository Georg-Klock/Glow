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
                calendar: calendar
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

    private func row(
        target: Int, done: [Int] = [], todayColumn: Int
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week,
            today: day(todayColumn),
            target: target,
            calendar: calendar
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
            in: week, today: later, target: 2, calendar: calendar
        )
        #expect(shape(spans) == "filled:0-5 missed:6-6")
    }

    @Test("A week that has not started divides evenly")
    func futureWeek() {
        let earlier = TestCalendar.date(2026, 8, 10)
        let spans = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2)),
            in: week, today: earlier, target: 2, calendar: calendar
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
                in: week, today: later, target: target, calendar: calendar
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
            in: week, today: day(4), target: 2, calendar: calendar
        )
        #expect(met.allSatisfy { $0.mark == .upcoming })
        // And the two that are still marks keep their own.
        let partial = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2)),
            in: week, today: day(6), target: 2, calendar: calendar
        )
        #expect(partial.map(\.mark) == [.missed, .openToday])
    }
}
