import Foundation
import Testing
@testable import Glow

/// **A habit made part-way into the week is granted the minimum credit that
/// avoids a ✕** (#343, `docs/week-marks.md` §6).
///
/// A habit made on Friday has not failed the Monday it did not exist for. The
/// *minimum* is the rule and it is the part worth testing: granting every
/// pre-creation day would collapse the remaining reps into one wide pill, which
/// reads as slack the habit does not have.
@Suite("Creation credit")
struct CreationCreditTests {
    private let calendar = TestCalendar.monday
    /// The week beginning Monday 2026-08-17.
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }

    /// A habit created on `column` of this week, with the target it was made
    /// with — which is what freezes the grant.
    private func habit(
        target: Int, createdOn column: Int?, madeWith atCreation: Int?? = nil, done: [Int] = []
    ) -> HabitSnapshot {
        let week = week
        return HabitSnapshot(
            id: UUID(), name: "Test", icon: "star",
            frequency: .timesPerWeek(target),
            completionCounts: done.reduce(into: [:]) { $0[week.days[$1]] = 1 },
            createdDay: column.map { week.days[$0] },
            // Double optional so a caller can say *explicitly nil* — a row that
            // never recorded a target — as distinct from "not specified, use
            // the current one".
            targetAtCreation: atCreation ?? (column == nil ? nil : target)
        )
    }

    private func spans(_ habit: HabitSnapshot, target: Int, today: Int) -> [SlotSpan] {
        WeekSpans.spans(
            for: habit, in: week, today: week.days[today], target: target,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
    }

    private func shape(_ habit: HabitSnapshot, target: Int, today: Int) -> String {
        spans(habit, target: target, today: today)
            .map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }.joined(separator: " ")
    }

    // MARK: - §6's own figures

    @Test("Five a week made on Friday asks for three, over the three days it has")
    func fiveAWeekMadeOnFriday() {
        // §6: `[·  ·][·  ·][○][·][·]` — two credit marks packing left, then the
        // three reps still owed. Credit is `max(0, 5 − 3)`, and the three days
        // are Friday, Saturday and Sunday: the creation day counts itself.
        #expect(shape(habit(target: 5, createdOn: 4), target: 5, today: 4)
            == "inactive:0-1 inactive:2-3 open:4-4 inactive:5-5 inactive:6-6")
    }

    @Test("Seven a week made on Friday still reads as a seven a week")
    func sevenAWeekMadeOnFriday() {
        // §6: `[·][·][·][·][○][·][·]`. Four granted, three owed, and the row's
        // silhouette still says what the habit *is* — which is invariant 1
        // doing its job through a case that could easily have broken it.
        #expect(shape(habit(target: 7, createdOn: 4), target: 7, today: 4)
            == "inactive:0-0 inactive:1-1 inactive:2-2 inactive:3-3 open:4-4 "
                + "inactive:5-5 inactive:6-6")
    }

    @Test("A habit is never born already failing")
    func aNewHabitHasNoCross() {
        // **On the day it is made**, on any target, made on any weekday: no ✕.
        // That is what "the minimum credit that avoids a ✕" claims, and the
        // inequality behind it is exactly tight — `credit` is
        // `max(0, target − daysLeft)`, so what is still owed is at most
        // `daysLeft` and no day can have run out yet (§5.1).
        //
        // It is *only* a claim about that day. A rep that goes unused after the
        // habit exists dies like any other; forgiving those would be the app
        // pretending a habit made on Friday is exempt for the rest of the week.
        for target in 1...7 {
            for created in 0...6 {
                let row = shape(habit(target: target, createdOn: created), target: target, today: created)
                #expect(!row.contains("missed"),
                        "target \(target), made on \(created): \(row)")
            }
        }
    }

    @Test("A rep that goes unused after the habit exists still dies")
    func creditDoesNotForgiveTheDaysAfter() {
        // The other side of the rule, so the test above cannot be read as
        // "a mid-week habit never gets a ✕". Made on Monday at five a week and
        // left alone until Sunday: nothing was granted, and the reps that ran
        // out of days say so.
        let row = shape(habit(target: 5, createdOn: 0), target: 5, today: 6)
        #expect(row.contains("missed"), "\(row)")
    }

    // MARK: - Frozen, and only shrinking

    @Test("An upward edit gets no amnesty")
    func upwardEditKeepsTheOldGrant() {
        // §6's table: 5x → 7x is `min(2, 4) = 2`, unchanged. The grant was for
        // days that did not exist, and editing the target does not change how
        // many of those there were.
        let edited = habit(target: 7, createdOn: 4, madeWith: 5)
        // Two credit marks, not the four a 7x made on Friday would get. The row
        // therefore owes five over three days and two of them die — which is
        // **§5.1's float case, the only place a ✕ lies about its day**: there is
        // no blank column the habit existed on to pin them to, so they lose
        // their anchor and take the leftmost free columns.
        #expect(shape(edited, target: 7, today: 4)
            == "inactive:0-0 inactive:1-1 missed:2-2 missed:3-3 open:4-4 "
                + "inactive:5-5 inactive:6-6")

        // Made *as* a 7x on the same day, nothing dies: the grant matches the
        // target and §5.1's inequality holds.
        #expect(!shape(habit(target: 7, createdOn: 4), target: 7, today: 4).contains("missed"))
    }

    @Test("A downward edit shrinks the grant to nothing")
    func downwardEditDropsTheGrant() {
        // §6's table: 5x → 3x is `min(2, 0) = 0`, and 5x → 2x likewise.
        // Otherwise the row meets its goal off credit nobody earned — at 2x the
        // two granted reps would be the whole target.
        for target in [3, 2] {
            let edited = habit(target: target, createdOn: 4, madeWith: 5)
            let row = shape(edited, target: target, today: 4)
            #expect(!row.contains("missed"), "target \(target): \(row)")
            // Every mark is owed, none granted: the open one plus the rest.
            #expect(row.components(separatedBy: " ").count == target, "target \(target): \(row)")
        }
    }

    // MARK: - A completion on a day before the habit existed (#415)

    @Test("A day before creation that was logged is not a day that was forgiven")
    func aBackfilledDayIsNotForgiven() {
        // Six a week made on Wednesday, with Monday and Tuesday logged —
        // `DemoHistory.seed` writes exactly this, because it hands every habit
        // to `SeededHistory.completions` with no bound from `createdDay`, and
        // #265 lets a daily row back-fill one by hand.
        //
        // Capacity is seven against a target of six: five days from Wednesday,
        // plus the two days that already carried a rep. Nothing is unavoidable,
        // so **the minimum credit that avoids a ✕ is none**, and the row is an
        // ordinary one — two done, one open on Wednesday, three still to come.
        let backfilled = habit(target: 6, createdOn: 2, done: [0, 1])
        #expect(shape(backfilled, target: 6, today: 2)
            == "filled:0-0 filled:1-1 open:2-2 inactive:3-3 inactive:4-4 inactive:5-6")

        // Without the back-fill the same habit is granted one, because then the
        // five days it has really are all it has.
        #expect(shape(habit(target: 6, createdOn: 2), target: 6, today: 2)
            == "inactive:0-1 open:2-2 inactive:3-3 inactive:4-4 inactive:5-5 inactive:6-6")
    }

    @Test("An over-granted credit mark pushes the ring off today")
    func theOverGrantMovedTheRing() {
        // What #415 reported, and why the over-grant is not merely arithmetic.
        // The grant is a *mark*: it takes column 0, so Monday's completion
        // clamps up to column 1 and Tuesday's to column 2, and by the time
        // `assignColumns` reaches the open mark the lowest column left is
        // Thursday. The ring came out on a day that is not today — §3
        // invariant 4 and §4.2 — while `actionDay` stayed on Wednesday, so a
        // tap still did the right thing and only the drawing lied.
        let made = habit(target: 6, createdOn: 2, done: [0, 1])
        let row = spans(made, target: 6, today: 2)
        let open = row.first { $0.state == .open }
        let what = Comment(rawValue: shape(made, target: 6, today: 2))
        #expect(open?.firstDay == 2, what)
        #expect(open?.lastDay == 2, what)
        #expect(open?.actionDay == week.days[2], what)
    }

    @Test("A backfilled week never moves the ring off today")
    func theRingStaysOnTodayThroughEveryBackfill() {
        // The whole space this suite can reach: every target, every one of the
        // 128 completion patterns, every today, and every creation day up to
        // it, made with the target it still has. `Glow/Logic/` compiles
        // standalone, so #415 swept the wider space — `targetAtCreation` free
        // as well, 250,880 rows — and found 491 rows whose open mark did not
        // contain today. Every one of them had a creation day inside the week,
        // a completion before it, and a non-zero grant.
        for target in 1...7 {
            for pattern in 0..<128 {
                let done = (0...6).filter { pattern & (1 << $0) != 0 }
                for todayColumn in 0...6 {
                    for created in 0...todayColumn {
                        let row = spans(
                            habit(target: target, createdOn: created, done: done),
                            target: target, today: todayColumn
                        )
                        let what = Comment(rawValue:
                            "\(target)x, today \(todayColumn), made \(created), done \(done): "
                                + row.map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }
                                    .joined(separator: " "))
                        // Credit still decides how many rep marks exist. #476
                        // deliberately leaves future columns blank when the
                        // open rep is last, and a one-day loss can leave a
                        // pre-creation day unclaimed, so full-week tiling is no
                        // longer an invariant of a live row.
                        #expect(row.count == target, what)
                        for (a, b) in zip(row, row.dropFirst()) {
                            #expect(b.firstDay > a.lastDay, what)
                        }
                        // Invariant 4, and §4.2.
                        let open = row.filter { $0.state == .open }
                        #expect(open.count <= 1, what)
                        guard let mark = open.first else { continue }
                        #expect(mark.firstDay <= todayColumn && todayColumn <= mark.lastDay, what)
                        #expect(mark.lastDay == todayColumn, what)
                    }
                }
            }
        }
    }

    // MARK: - Who gets nothing

    @Test("A habit that lived the whole week is granted nothing")
    func aFullWeekEarnsNoCredit() {
        // Created on Monday, the first column: there are no days before it to
        // forgive, so the row is an ordinary one.
        #expect(shape(habit(target: 3, createdOn: 0), target: 3, today: 0)
            == shape(habit(target: 3, createdOn: nil), target: 3, today: 0))
    }

    @Test("A row that never recorded its target is granted nothing")
    func anUnknownTargetEarnsNoCredit() {
        // `targetAtCreation` nil means the row predates the column. An unknown
        // grant cannot be reconstructed, and claiming one would be the app
        // inventing forgiveness it has no record of — the same rule
        // `createdDay` follows (#186, #265).
        let unknown = habit(target: 5, createdOn: 4, madeWith: .some(nil))
        #expect(unknown.targetAtCreation == nil)
        let known = habit(target: 5, createdOn: 4)
        #expect(shape(unknown, target: 5, today: 4) != shape(known, target: 5, today: 4))
        // Without a grant the days it did not exist for are accused, which is
        // exactly the wrong the grant exists to prevent — and exactly what a
        // pre-column row already looked like before #343.
        #expect(shape(unknown, target: 5, today: 4).contains("missed"))
    }

    @Test("A new habit records the target it was made with")
    func creationRecordsTheTarget() {
        // The freeze is only as good as the write. A habit made through the
        // model's own initialiser carries its target; a spacer has no cadence
        // to freeze.
        let made = Habit(
            name: "Read", icon: "book", frequency: .timesPerWeek(4),
            createdAt: TestCalendar.date(2026, 8, 21), sortOrder: 0
        )
        #expect(made.targetAtCreation == 4)
        #expect(made.snapshot(calendar: calendar).targetAtCreation == 4)

        let spacer = Habit(
            name: "", icon: "", frequency: .daily,
            createdAt: TestCalendar.date(2026, 8, 21), sortOrder: 1, isSpacer: true
        )
        #expect(spacer.targetAtCreation == nil)
    }
}
