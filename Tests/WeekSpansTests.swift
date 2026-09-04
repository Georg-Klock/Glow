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

    @Test("Two a week, one done earlier: the completion keeps its day and open stops today")
    func openSpanStartsAtToday() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [TestCalendar.date(2026, 8, 18)]  // Tuesday
        )
        let row = spans(habit, target: 2)

        // The completion anchors on Tuesday and reaches back over Monday
        // (#339); it used to be handed the whole block before today, which put
        // its edge on Thursday — a day nothing happened on. The final open mark
        // reaches back from Wednesday and owns the rest of the row (#495).
        #expect(row.count == 2)
        #expect(row[0].state == .filled)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 1)  // Monday and Tuesday
        #expect(row[1].state == .open)
        #expect(row[1].firstDay == 2 && row[1].lastDay == 6)  // Wednesday through Sunday
    }

    @Test("The row #389 reported now draws its one-day cross on Monday")
    func theRowThatReportedItDrawsItsCrossOnMonday() {
        // #389 read a screen as `4x, completions Thursday and Friday, today
        // Saturday` and could not reproduce it — those facts divide the week
        // cleanly, with two reps owed against Saturday and Sunday and no ✕ at
        // all. A ✕ needs `target − credit ≥ 5` there, and the seed is 4.
        //
        // The row that draws what was actually photographed is this one: **one
        // completion, not two**. Three owed against two actionable days is one
        // lost rep. #476 makes it one day on Monday, the earliest blank day it
        // could have used.
        let clean = spans(
            .fixture(
                frequency: .timesPerWeek(4),
                completedDays: [TestCalendar.date(2026, 8, 20), TestCalendar.date(2026, 8, 21)]
            ),
            target: 4,
            today: TestCalendar.date(2026, 8, 22)
        )
        #expect(!clean.contains { $0.state == .missed })

        let reported = spans(
            .fixture(
                frequency: .timesPerWeek(4),
                completedDays: [TestCalendar.date(2026, 8, 21)]  // Friday only
            ),
            target: 4,
            today: TestCalendar.date(2026, 8, 22)
        )
        #expect(reported.count == 4)
        let dead = reported.first { $0.state == .missed }
        // #476 supersedes the stretched cross entirely: the rep gets one day,
        // Monday, and the completion/open marks absorb the released columns.
        #expect(dead?.firstDay == 0 && dead?.lastDay == 0)
    }

    @Test("One completed one-a-week goal is one span")
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

    @Test("Spans remain ordered and tile the whole week")
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

    @Test("Every completion past the goal keeps its own bonus mark")
    func extraCompletionsBecomeBonusMarks() {
        // A habit edited from 5x down to 2x keeps its completions.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: Set(week.days.prefix(5))
        )
        let row = spans(habit, target: 2)

        // Five recorded days make five marks. The required two remain ordinary;
        // all three extras are explicitly bonus marks, and the latest one owns
        // the remainder of the week (#543).
        #expect(row.count == 5)
        #expect(row.map(\.isBonus) == [false, false, true, true, true])
        #expect(row.dropLast().enumerated().allSatisfy { offset, mark in
            mark.firstDay == offset && mark.lastDay == offset
        })
        #expect(row.last?.firstDay == 4 && row.last?.lastDay == 6)
        #expect(
            row.filter(\.isBonus).compactMap(\.completionDay)
                == Array(week.days[2...4])
        )
    }

    @Test("The natural bonus cap is all seven civil days")
    func bonusMarksCapAtTheWeek() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(1),
            completedDays: Set(week.days)
        )
        let row = spans(habit, target: 1)

        #expect(row.count == 7)
        #expect(row.count(where: \.isBonus) == 6)
        #expect(row.first?.firstDay == 0)
        #expect(row.last?.firstDay == 6 && row.last?.lastDay == 6)
    }
}

/// #476 and #495: one rep owns one claimable window. An open mark stops on
/// today while another rep follows; when it is final, it owns the remainder of
/// the week. Future windows get longer away from today, and a loss is a one-day
/// cross rather than a pill.
@Suite("Claimable rep windows")
struct ClaimableRepWindowTests {
    private let calendar = TestCalendar.monday
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }

    private func row(
        target: Int,
        done: [Int] = [],
        todayColumn: Int,
        editing: SlotEditing = .todayOnly
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { week.days[$0] })
            ),
            in: week,
            today: week.days[todayColumn],
            target: target,
            editing: editing,
            restDay: nil,
            calendar: calendar
        )
    }

    private func pastRow(target: Int, done: [Int] = []) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { week.days[$0] })
            ),
            in: week,
            today: TestCalendar.date(2026, 8, 24),
            target: target,
            editing: .todayOnly,
            restDay: nil,
            calendar: calendar
        )
    }

    private func shape(_ spans: [SlotSpan]) -> String {
        spans.map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }
            .joined(separator: " ")
    }

    @Test("Three skipped reps grow backward while future windows shorten near today")
    func blankThreePerWeek() {
        let expected = [
            "open:0-0 inactive:1-3 inactive:4-6",
            "open:0-1 inactive:2-3 inactive:4-6",
            "open:0-2 inactive:3-4 inactive:5-6",
            "open:0-3 inactive:4-4 inactive:5-6",
            "open:0-4 inactive:5-5 inactive:6-6",
            "missed:0-0 open:1-5 inactive:6-6",
            "missed:0-0 missed:1-1 open:2-6",
        ]
        for today in 0...6 {
            #expect(shape(row(target: 3, todayColumn: today)) == expected[today])
        }
    }

    @Test("A Monday completion pushes the open window to Tuesday")
    func completedMonday() {
        let expected = [
            "filled:0-0 inactive:1-3 inactive:4-6",
            "filled:0-0 open:1-1 inactive:2-6",
            "filled:0-0 open:1-2 inactive:3-6",
            "filled:0-0 open:1-3 inactive:4-6",
            "filled:0-0 open:1-4 inactive:5-6",
            "filled:0-0 open:1-5 inactive:6-6",
            "filled:0-0 missed:1-1 open:2-6",
        ]
        for today in 0...6 {
            #expect(shape(row(target: 3, done: [0], todayColumn: today)) == expected[today])
        }
    }

    @Test("Completing today settles only the open window")
    func completionDoesNotRedistributeUntilTomorrow() {
        #expect(shape(row(target: 3, todayColumn: 1))
            == "open:0-1 inactive:2-3 inactive:4-6")
        #expect(shape(row(target: 3, done: [1], todayColumn: 1))
            == "filled:0-1 inactive:2-3 inactive:4-6")
    }

    @Test("Only the final open rep owns the rest of the week")
    func lastOpenRepOwnsTheRemainder() {
        #expect(shape(row(target: 1, todayColumn: 0)) == "open:0-6")
        #expect(shape(row(target: 2, done: [0], todayColumn: 1))
            == "filled:0-0 open:1-6")
        #expect(shape(row(target: 3, done: [0], todayColumn: 1))
            == "filled:0-0 open:1-1 inactive:2-6")
        #expect(shape(row(target: 2, done: [0, 1], todayColumn: 1))
            == "filled:0-0 filled:1-6")
    }

    @Test("An unfinished loss is one cross on the first claimable day")
    func lostRepIsNotAPill() {
        let saturday = row(target: 3, todayColumn: 5)
        #expect(saturday.first?.state == .missed)
        #expect(saturday.first?.firstDay == 0)
        #expect(saturday.first?.lastDay == 0)
        #expect(saturday[1].firstDay == 1 && saturday[1].lastDay == 5)
    }

    @Test("A finished missed week crosses every uncompleted day")
    func finishedMissedWeekIsADiary() {
        #expect(shape(pastRow(target: 3, done: [0]))
            == "filled:0-0 missed:1-1 missed:2-2 missed:3-3 missed:4-4 missed:5-5 missed:6-6")
    }

    @Test("A finished met week has completed pills and no crosses")
    func finishedMetWeekHasNoCrosses() {
        let row = pastRow(target: 2, done: [0, 1])
        #expect(shape(row) == "filled:0-0 filled:1-6")
        #expect(!row.contains { $0.state == .missed })
    }

    @Test("A normal week keeps every open action on today")
    func openActionsStayOnToday() {
        for target in 1...7 {
            for today in 0...6 {
                let spans = row(
                    target: target,
                    todayColumn: today,
                    editing: .todayOnly
                )
                for span in spans where span.state == .open {
                    #expect(span.actionDay == week.days[today])
                }
            }
        }
    }

    @Test("A final open span still acts on today rather than its future edge")
    func finalOpenSpanActsOnToday() {
        let spans = row(
            target: 2,
            done: [0],
            todayColumn: 1,
            editing: .todayOnly
        )
        let open = spans.last

        #expect(open?.state == .open)
        #expect(open?.firstDay == 1 && open?.lastDay == 6)
        #expect(open?.actionDay == week.days[1])
    }
}

/// A current weekly row draws `target` spans until a genuine bonus completion
/// adds another. A finished unmet week is tested separately as #476's
/// seven-day diary.
/// The suite above is the design file's examples; this one covers the current
/// days the file did not draw.
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
        #expect(shape(row(target: 2, todayColumn: 6)) == "missed:0-0 open:1-6")
        #expect(shape(row(target: 3, todayColumn: 5)) == "missed:0-0 open:1-5 inactive:6-6")
        #expect(shape(row(target: 3, todayColumn: 6)) == "missed:0-0 missed:1-1 open:2-6")
    }

    @Test("A completion keeps its day, and the lost rep keeps one day")
    func completedBlockYields() {
        // Three a week, one logged on Monday, and it is Sunday. Two reps are
        // owed against one day, so one is gone. It is Tuesday's one-day cross;
        // the open rep absorbs Wednesday through Sunday.
        #expect(shape(row(target: 3, done: [0], todayColumn: 6))
            == "filled:0-0 missed:1-1 open:2-6")
    }

    @Test("A rest day brings the squeeze forward a day")
    func restDayTable() {
        withRest(6) { rest in
            #expect(shape(row(target: 2, todayColumn: 4, restDay: rest)) == "open:0-4 inactive:5-6")
            #expect(shape(row(target: 2, todayColumn: 5, restDay: rest)) == "missed:0-4 open:5-6")
        }
    }

    @Test("A week already over crosses every blank day")
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
        #expect(shape(spans)
            == "filled:0-0 missed:1-1 missed:2-2 missed:3-3 missed:4-4 missed:5-5 missed:6-6")
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

    @Test("Every live row keeps its target, order, and open-day boundary")
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
                            let finalIsTruncatedOpen = rest == nil
                                && spans.last?.state == .open
                                && spans.last?.lastDay == todayColumn
                            #expect(spans.last?.lastDay == 6 || finalIsTruncatedOpen,
                                    "unexpected end — \(what)")
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

    @Test("A finished missed week crosses every blank day")
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
            #expect(spans.count { $0.state == .missed } == 7 - done,
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
    @Test("A cadence span carries today and no correction days")
    func spansCarryTodayOnly() {
        // Sunday, three a week, nothing logged: two reps have run out of days
        // and the third is open. On the widget only the open span acts.
        let widget = row(target: 3, todayColumn: 6)
        #expect(shape(widget) == "missed:0-0 missed:1-1 open:2-6")
        #expect(widget.map(\.actionDay) == [nil, nil, day(6)])

    }

    @Test("A span entirely ahead of today is inert")
    func futureSpansAreInert() {
        // Friday, two a week: the open span runs to today and the weekend span
        // is entirely in the future.
        #expect(shape(row(target: 2, todayColumn: 4)) == "open:0-4 inactive:5-6")

        let plain = row(target: 2, todayColumn: 4, editing: .todayOnly)
        #expect(plain.map(\.actionDay) == [day(4), nil])
    }

    // MARK: - A completion ahead of today (#382)

    @Test("A completion logged after today does not displace the open mark")
    func aheadOfTodayKeepsTheOpenMarkOnToday() {
        // Friday, one completion logged on Sunday through Edit History. The
        // open mark used to be
        // appended *after* the anchored marks rather than sorted into them, so
        // in a list `assignColumns` reads left to right the two swapped: at 2x
        // the ring was drawn on Sunday and at 3x on Saturday, and the
        // completion's own mark ended before the day it was logged on.
        #expect(shape(row(target: 2, done: [6], todayColumn: 4)) == "open:0-4 filled:5-6")
        #expect(shape(row(target: 3, done: [6], todayColumn: 4))
            == "open:0-4 filled:5-5 inactive:6-6")

        // The ring is today's, and it now ends there as well as acting there.
        let app = row(target: 2, done: [6], todayColumn: 4, editing: .todayOnly)
        #expect(app.first { $0.state == .open }?.lastDay == 4)
        #expect(app.first { $0.state == .open }?.actionDay == day(4))
    }

    @Test("A completion ahead of today keeps its own day where the columns allow")
    func aheadOfTodayKeepsItsDay() {
        // 2x: one rep owed after Sunday's, so the completion is the last mark
        // and ends on the final column — its own. At 3x a rep still to come
        // needs a column behind it, and the clamp takes Sunday off the record
        // rather than off the rep: that is the documented trade in
        // `assignColumns`, not this fix.
        let two = row(target: 2, done: [6], todayColumn: 4)
        #expect(two.first { $0.state == .filled }?.lastDay == 6)
    }

    @Test("A completion ahead of a spent today keeps its place after it")
    func aheadOfASpentTodayStaysAfterIt() {
        // Today logged as well as Sunday. There is no open mark once today is
        // spent — what follows the completions is arithmetic that divides, and
        // arithmetic has no day, so it cannot sort by one.
        #expect(shape(row(target: 3, done: [4, 6], todayColumn: 4))
            == "filled:0-4 filled:5-5 inactive:6-6")
        #expect(!row(target: 3, done: [4, 6], todayColumn: 4).contains { $0.state == .open })
    }

    @Test("Logging ahead never moves the ring off today", arguments: 0...6)
    func theRingStaysOnToday(aheadColumn: Int) {
        for todayColumn in 0...6 where aheadColumn > todayColumn {
            for target in 1...7 {
                let spans = row(target: target, done: [aheadColumn], todayColumn: todayColumn)
                guard let open = spans.first(where: { $0.state == .open }) else { continue }
                let what = Comment(
                    rawValue: "\(target)x, today \(todayColumn), "
                        + "logged \(aheadColumn): \(shape(spans))"
                )
                #expect(open.firstDay <= todayColumn && todayColumn <= open.lastDay, what)
                // Even with a future completion in the record, the ring still
                // contains today. It may extend only when it is the final mark;
                // the normal surface's action remains pinned to today (#495).
                if open == spans.last {
                    #expect(open.lastDay == 6, what)
                } else {
                    #expect(open.lastDay == todayColumn, what)
                }
                #expect(open.actionDay == day(todayColumn), what)
            }
        }
    }

    // MARK: - Undoing a span lands on a day that was logged (#256)

    /// The cadence surface, whose only writable day is today.
    private func weekRow(
        target: Int, done: [Int], today: Date? = nil, restDay: Int? = nil
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { day($0) })
            ),
            in: week, today: today ?? day(4), target: target,
            editing: .todayOnly, restDay: restDay, calendar: calendar
        )
    }

    /// **A filled span may only hand out a day it can actually undo** (#256).
    ///
    /// `HabitStore.toggleCompletion` is a per-day toggle: on a day carrying no
    /// completion it *adds* one. So a filled span whose `actionDay` is a day
    /// with nothing logged does not un-complete anything when it is activated —
    /// it logs a new day. On a row whose goal is already met that is invisible
    /// in the old spans, because `done` was clamped to `target`; #543 now gives
    /// that extra completion a visible bonus mark, while this test still pins
    /// the today-only cadence interaction boundary.
    ///
    /// That is the whole of the report in #256, which read as "un-completing
    /// mostly does not register". It registers exactly when the finger lands on
    /// one of the columns that carries a dot, and those are the minority of the
    /// bar. Worse, every miss adds a completion, so the next correct tap has one
    /// more to remove before the row can drop below its target — the failure
    /// compounds.
    @Test("A filled span without a completion today is browse-only")
    func pastFilledSpanIsInert() {
        // One a week, logged on Tuesday, today is Friday: goal met, one span
        // across the whole week. Tuesday is visible, but only Edit History can
        // correct it now.
        let row = weekRow(target: 1, done: [1])
        #expect(row.count == 1)
        #expect(row[0].state == .filled)
        #expect(row[0].actionDay == nil)
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
        target: Int, done: [Int] = [], editing: SlotEditing = .todayOnly,
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

    @Test("A finished week draws completed pills or a day-by-day missed diary")
    func pastWeekInvariantsHold() {
        for rest in [nil, 0, 3, 6] as [Int?] {
            withRest(rest) { restDay in
                for target in 1...6 {
                    for doneCount in 0...target {
                        let done = Array(0..<doneCount)
                        let spans = pastRow(target: target, done: done, restDay: restDay)
                        let what = "target \(target), done \(doneCount), rest \(String(describing: rest)): \(shape(spans))"

                        // #476: an unmet seven-day week is seven day-sized
                        // facts. A met goal still has one completed pill per
                        // target, and a legacy rest-day row keeps its old rule.
                        let expectedCount = rest == nil && doneCount < target
                            ? 7
                            : target
                        #expect(spans.count == expectedCount, "span count — \(what)")
                        #expect(spans.first?.firstDay == 0, "starts at 0 — \(what)")
                        #expect(spans.last?.lastDay == 6, "ends at 6 — \(what)")
                        for (a, b) in zip(spans, spans.dropFirst()) {
                            #expect(b.firstDay == a.lastDay + 1, "gap — \(what)")
                        }
                        // R1: a week that is over has nothing open in it.
                        #expect(!spans.contains { $0.state == .open }, "open — \(what)")

                        #expect(
                            spans.allSatisfy { !$0.isTappable },
                            "a finished week exposed a cadence correction — \(what)"
                        )
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

    @Test("Logging a day in a finished missed week replaces that day's cross")
    func aLateCompletionUnmakesACross() {
        // Three a week, one logged: every other finished day is a cross.
        let before = pastRow(target: 3, done: [0])
        #expect(shape(before)
            == "filled:0-0 missed:1-1 missed:2-2 missed:3-3 missed:4-4 missed:5-5 missed:6-6")
        #expect(before.count { $0.state == .missed } == 6)

        // Correct the record through Edit History and the arithmetic re-runs:
        // the rep happened, late, so it is no longer lost.
        let after = pastRow(target: 3, done: [0, 2])
        #expect(after.count { $0.state == .missed } == 5)
        #expect(after.count == 7)

        // And filling it out entirely stops the week being divided at all.
        let met = pastRow(target: 3, done: [0, 2, 4])
        #expect(shape(met) == "filled:0-0 filled:1-2 filled:3-6")
    }

    @Test("A span never carries the legacy rest day")
    func spansNeverCarryTheRestDay() {
        withRest(6) { rest in
            // Sunday rests, so the span covering the weekend hands out Saturday
            // rather than the day nothing can happen on.
            let result = row(
                target: 2, todayColumn: 4,
                editing: .todayOnly, restDay: rest
            )
            #expect(shape(result) == "open:0-4 inactive:5-6")
            #expect(result.map(\.actionDay) == [day(4), nil])
        }

        withRest(0) { rest in
            // Monday rests and is in the past: no span may carry it.
            let result = row(
                target: 3, todayColumn: 6,
                editing: .todayOnly, restDay: rest
            )
            for span in result {
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

    @Test("An achieved span is lit, and a met week is not an untouched one")
    func achievedSpansAreLit() {
        // **The reversal of #47** (#344). This test used to assert the
        // opposite — that a met goal and an untouched week draw the same marks,
        // with the dots the only thing telling them apart. They must not: a
        // completion is lit on every surface (SPEC §1), and once a mark ends on
        // its own day (#339) the dots were saying what the mark already said.
        let met = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2), completedDays: [day(0), day(1)]),
            in: week, today: day(4), target: 2,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        // `donePast`, not `doneToday`: a span covers a run of days rather than
        // one, and under the two tiers (#334) a completion is lit but does not
        // emit.
        #expect(met.allSatisfy { $0.mark == .donePast })

        // The week that asked for the same two reps and got none of them is
        // the picture a met row must not be confusable with.
        let untouched = WeekSpans.spans(
            for: .fixture(frequency: .timesPerWeek(2)),
            in: week, today: day(4), target: 2,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(untouched.allSatisfy { $0.mark != .donePast })

        // And the two that were always marks keep their own.
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
            editing: .todayOnly, restDay: nil, calendar: calendar
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

    @Test("Every touched span keeps its division through completion and undo")
    func everyTouchedSpanKeepsIdentity() {
        var checkedTransitions = 0

        // Sweep every target, weekday and completion subset. A configuration
        // participates only when today owns an open action: adding today is
        // then the exact production completion, and reading the same pair in
        // reverse is its undo. Keeping the Division across both directions is
        // what lets SpanView change state in place instead of disappearing for
        // one background-only frame (#498).
        for target in 1...7 {
            for todayColumn in 0...6 {
                for mask in 0..<(1 << 7) where mask & (1 << todayColumn) == 0 {
                    let done = (0...6).filter { mask & (1 << $0) != 0 }
                    let before = row(target: target, done: done, todayColumn: todayColumn)
                    guard let touched = before.first(where: {
                        $0.state == .open && $0.actionDay == day(todayColumn)
                    }) else { continue }

                    let after = row(
                        target: target,
                        done: done + [todayColumn],
                        todayColumn: todayColumn
                    )
                    let settled = after.first(where: { $0.id == touched.id })
                    let what = "\(target)x, today \(todayColumn), done \(done): "
                        + "\(shape(before)) -> \(shape(after))"

                    #expect(settled?.state == .filled, "identity changed — \(what)")
                    #expect(settled?.actionDay == day(todayColumn), "wrong undo day — \(what)")
                    checkedTransitions += 1
                }
            }
        }

        #expect(checkedTransitions > 0, "the sweep found no tappable open spans")
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
                        // Completions on days that have arrived, off the rest
                        // day. Not because the other two are unreachable — they
                        // are, and #381 is the crash that proved it — but
                        // because the properties below are stated in terms of
                        // *past* completions and a future one is not the same
                        // claim. `LaterCompletionTests` sweeps the wider space
                        // for the invariants that hold everywhere.
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
                            editing: .todayOnly, restDay: restDay, calendar: calendar
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

    @Test("A row draws its target or every completion, whichever is greater")
    func targetPlusBonusMarks() {
        everyRow { row in
            #expect(row.spans.count == max(row.target, row.done.count), "mark count — \(row.what)")
        }
    }

    @Test("The marks are ordered and tile the week")
    func marksTileTheWeek() {
        everyRow { row in
            #expect(row.spans.first?.firstDay == 0, "starts at 0 — \(row.what)")
            #expect(row.spans.last?.lastDay == 6, "unexpected end — \(row.what)")
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
            // Bonus completions have marks of their own, so every logged day
            // remains inside a lit fact rather than merely inside another
            // completion's trailing remainder.
            for column in row.done {
                let mark = row.spans.first { $0.firstDay <= column && column <= $0.lastDay }
                #expect(mark?.state == .filled, "day \(column) is not filled — \(row.what)")
            }
        }
    }

    @Test("A ✕ never outnumbers the days one could have been pinned to")
    func everyCrossHasADayOfItsOwn() {
        everyRow { row in
            // **No mark carries two ✕** (invariant 6). A lost rep pins to a
            // blank past day of its own, so the row cannot draw more crosses
            // than it has such days — if it ever did, two would be sharing a
            // mark and one of them would be invisible.
            let blankPast = (0...6).count {
                $0 < row.todayColumn && $0 != row.restColumn && !row.done.contains($0)
            }
            let crosses = row.spans.count { $0.state == .missed }
            #expect(crosses <= blankPast, "more ✕ than blank past days — \(row.what)")
        }
    }

    @Test("Backfilling a day never adds a ✕")
    func backfillingNeverAddsACross() {
        everyRow { row in
            // A ✕ is a rep that ran out of days. Logging a day can only remove
            // reps from the owed count, never add one, so correcting the past
            // must never make the row accuse more than it did — the property
            // that makes a ✕ safe to leave tappable in the week view (#116).
            let before = row.spans.count { $0.state == .missed }
            let week = self.week
            for day in 0...row.todayColumn
            where !row.done.contains(day) && day != row.restColumn {
                let after = WeekSpans.spans(
                    for: .fixture(
                        frequency: .timesPerWeek(row.target),
                        completedDays: Set((row.done + [day]).map { week.days[$0] })
                    ),
                    in: week, today: week.days[row.todayColumn], target: row.target,
                    editing: .todayOnly,
                    restDay: row.restColumn.map { TestPreferences.weekday(ofColumn: $0, in: week) },
                    calendar: calendar
                ).count { $0.state == .missed }
                #expect(after <= before, "logging day \(day) added a ✕ — \(row.what)")
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
            guard !row.spans.contains(where: { $0.state == .missed }),
                  row.done.last.map({
                      $0 + max(0, row.target - row.done.count) <= 6
                  }) ?? true
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

/// The two ways a completion stops being in the past, and the crash they were
/// (#381).
///
/// `MarkInvariantsTests` sweeps completions on days that have arrived, off the
/// rest day, and said in a comment that the other rows were states "the app
/// can[not] reach". Both halves of that were wrong:
///
/// - **The rest day is a setting**, so the app cannot reach a *write* on it —
///   `SlotEditing.day` and `HabitStore.setCompletion` both refuse one — but a
///   day logged on Tuesday becomes a rest-day column the moment Settings moves
///   the rest day to Tuesday. Nothing rewrites the record, and nothing should:
///   the completion happened.
/// - **A later day of this week is writable** through Edit History, which
///   explicitly asks `HabitStore.toggleCompletion(_:on:allowingFuture:)` for
///   that exception while cadence surfaces remain today-only.
///
/// Either one put a completion on a day `actionableLeft` was still counting as
/// free while `deadDays` had already spent it, so `lost` came out below
/// `dead.count` and `Array(repeating:count:)` was handed a negative count.
/// `EXC_BREAKPOINT`, on every redraw of the week — which is to say a crash
/// loop, because the completion is stored and the row is on the first screen.
/// Six TestFlight crashes on build `202608282309` were exactly this.
@Suite("Completions that are not in the past")
struct LaterCompletionTests {
    private let calendar = TestCalendar.monday
    /// Friday of the week beginning Monday 2026-08-24 — the week the crash
    /// logs were taken in.
    private let friday = TestCalendar.date(2026, 8, 28)
    private var week: Week { WeekCalendar.week(containing: friday, calendar: calendar) }

    private func spans(
        target: Int, done: [Int], todayColumn: Int, restColumn: Int?
    ) -> [SlotSpan] {
        WeekSpans.spans(
            for: .fixture(
                frequency: .timesPerWeek(target),
                completedDays: Set(done.map { week.days[$0] })
            ),
            in: week,
            today: week.days[todayColumn],
            target: target,
            editing: .todayOnly,
            restDay: restColumn.map { TestPreferences.weekday(ofColumn: $0, in: week) },
            calendar: calendar
        )
    }

    @Test("The rest day moving onto a logged day draws a row rather than trapping")
    func restDayMovedOntoACompletion() {
        // Three a week, Sunday logged, today Friday — and Friday is now the
        // rest day. Before the fix `lost` was 0 and `deadDays` found Thursday,
        // so the row asked for -1 crosses.
        let row = spans(target: 3, done: [6], todayColumn: 4, restColumn: 4)

        #expect(row.count == 3)
        #expect(row.first?.firstDay == 0)
        #expect(row.last?.lastDay == 6)
        #expect(row.count { $0.state == .filled } == 1)
    }

    @Test("A completion on a later day of this week draws a row rather than trapping")
    func completionAfterToday() {
        // Three a week, Sunday logged from the demo-seeded week view, today
        // Saturday, no rest day. Sunday cannot carry a second rep, so the third
        // one has run out of days — which is a ✕, not a trap.
        let row = spans(target: 3, done: [6], todayColumn: 5, restColumn: nil)

        #expect(row.count == 3)
        #expect(row.first?.firstDay == 0)
        #expect(row.last?.lastDay == 6)
        #expect(row.contains { $0.state == .missed })
    }

    @Test("Every completion pattern draws ordered marks that tile the week")
    func everyPatternDrawsItsTarget() {
        // The sweep `MarkInvariantsTests` excludes: all 128 subsets against
        // every today and every rest day, with no filter on when a completion
        // landed. Only the invariants that hold for any of them — the call
        // returns at all, the row holds its target or every completion when
        // bonuses exceed it, and those marks remain ordered. A final open or
        // completed mark owns the remainder of the week.
        for restColumn in [nil, 0, 3, 6] as [Int?] {
            for target in 1...7 {
                for todayColumn in 0...6 {
                    for pattern in 0..<128 {
                        let done = (0...6).filter { pattern & (1 << $0) != 0 }
                        let row = spans(
                            target: target, done: done,
                            todayColumn: todayColumn, restColumn: restColumn
                        )
                        let what = "target \(target), today \(todayColumn), done \(done), "
                            + "rest \(String(describing: restColumn)): "
                            + row.map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }
                                .joined(separator: " ")

                        #expect(row.count == max(target, done.count), "mark count — \(what)")
                        #expect(row.first?.firstDay == 0, "starts at 0 — \(what)")
                        #expect(row.last?.lastDay == 6, "unexpected end — \(what)")
                        for (a, b) in zip(row, row.dropFirst()) {
                            #expect(b.firstDay == a.lastDay + 1, "gap — \(what)")
                        }
                    }
                }
            }
        }
    }
}
