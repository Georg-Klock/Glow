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

    private func shape(_ habit: HabitSnapshot, target: Int, today: Int) -> String {
        WeekSpans.spans(
            for: habit, in: week, today: week.days[today], target: target,
            editing: .todayOnly, restDay: nil, calendar: calendar
        ).map { "\($0.state.rawValue):\($0.firstDay)-\($0.lastDay)" }.joined(separator: " ")
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
