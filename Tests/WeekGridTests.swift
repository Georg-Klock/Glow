import Foundation
import Testing
@testable import Glow

@Suite("Slot states")
struct WeekGridTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    /// Every test in this suite runs on a week with **no rest day** unless it
    /// asks for one, said out loud rather than inherited. This suite asserts
    /// R1, R2, R5 and R7 —
    /// including the exhaustive pass over all 128 completion histories — and a
    /// rest day arriving from elsewhere would change slot states underneath it
    /// (#105).
    ///
    /// Since #181 that is a property of the call rather than a hope about what
    /// else is running: the rest day is an argument, so nothing outside this
    /// file can set one for these assertions.
    ///
    /// `.todayOnly` unless a test says otherwise, so every assertion written
    /// before #116 still asserts what it was written to assert: the widget's
    /// rule, which is also what the app's rule used to be.
    private func slots(
        _ habit: HabitSnapshot,
        editing: SlotEditing = .todayOnly,
        restDay: Int? = nil
    ) -> [Slot] {
        WeekGrid.slots(
            for: habit, in: week, today: today, editing: editing,
            restDay: restDay, calendar: calendar
        )
    }

    // MARK: - Daily

    @Test("A daily habit shows exactly seven circles")
    func dailyRowHasSevenSlots() {
        #expect(slots(.fixture()).count == 7)
    }

    @Test("Today is open, past days are missed, future days are inactive")
    func dailyStates() {
        let row = slots(.fixture())

        // A day gone by without a completion is a different fact from a day
        // that has not arrived, and the grid draws them differently. They were
        // the same state until the states were separated.
        #expect(row[0].state == .missed)    // Monday, gone
        #expect(row[1].state == .missed)    // Tuesday, gone
        #expect(row[2].state == .open)      // Wednesday, today
        #expect(row[3].state == .inactive)  // Thursday, not yet
        #expect(row[6].state == .inactive)
    }

    @Test("A completion today and a completion on Monday are the same state, different marks")
    func marksSeparateTodayFromHistory() {
        let habit = HabitSnapshot.fixture(completedDays: [
            TestCalendar.date(2026, 8, 17),
            today
        ])
        let row = slots(habit)

        #expect(row[0].state == .filled)
        #expect(row[2].state == .filled)
        // Only today's completion is lit. This is the whole hierarchy: an
        // achievement stops asking for attention the moment it is recorded.
        #expect(row[0].mark == .donePast)
        #expect(row[2].mark == .doneToday)
    }

    @Test("Every state maps to exactly one mark")
    func markCoverage() {
        let row = slots(.fixture())

        #expect(row[0].mark == .missed)
        #expect(row[2].mark == .openToday)
        #expect(row[3].mark == .upcoming)
    }

    @Test("A habit due a number of times a week can never miss")
    func frequencyRowsNeverMiss() {
        // An empty slot on Wednesday is not a failure when the week is still
        // winnable, so these rows have no past to have missed.
        for target in 2...6 {
            let row = slots(.fixture(frequency: .timesPerWeek(target)))
            #expect(!row.contains { $0.state == .missed }, "\(target)x per week produced a miss")
            #expect(!row.contains { $0.mark == .missed })
        }
    }

    @Test("A completed day is filled, including today")
    func dailyCompleted() {
        let habit = HabitSnapshot.fixture(completedDays: [
            TestCalendar.date(2026, 8, 17),
            today
        ])
        let row = slots(habit)

        #expect(row[0].state == .filled)
        #expect(row[2].state == .filled)
        // Filled today is still tappable, so a mistaken tap can be undone.
        #expect(row[2].isTappable)
    }

    @Test("Only today's slot is tappable")
    func dailyTappability() {
        let row = slots(.fixture())
        let tappable = row.filter(\.isTappable)

        #expect(tappable.count == 1)
        #expect(tappable.first?.index == 2)
        #expect(tappable.first?.actionDay == today)
    }

    // MARK: - Times per week

    @Test("An N-times-per-week habit shows exactly N pills", arguments: 2...6)
    func frequencyRowSlotCount(target: Int) {
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(target))
        #expect(slots(habit).count == target)
    }

    @Test("Pills fill left to right, and the next one is open")
    func frequencyFillOrder() {
        // Two completions this week, logged on Monday and Tuesday.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(4),
            completedDays: [TestCalendar.date(2026, 8, 17), TestCalendar.date(2026, 8, 18)]
        )
        let row = slots(habit)

        #expect(row.map(\.state) == [.filled, .filled, .open, .inactive])
    }

    @Test("No slot is open once today is already logged")
    func frequencyDoneToday() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(4),
            completedDays: [TestCalendar.date(2026, 8, 17), today]
        )
        let row = slots(habit)

        #expect(row.map(\.state) == [.filled, .filled, .inactive, .inactive])
        // The pill holding today's completion is the one that can undo it.
        #expect(row.filter(\.isTappable).map(\.index) == [1])
    }

    @Test("No slot is open once the weekly goal is met")
    func frequencyGoalMet() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [TestCalendar.date(2026, 8, 17), TestCalendar.date(2026, 8, 18)]
        )
        let row = slots(habit)

        #expect(row.map(\.state) == [.filled, .filled])
        #expect(row.allSatisfy { !$0.isTappable })
    }

    @Test("Completions in other weeks do not fill this week's pills")
    func frequencyIgnoresOtherWeeks() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3),
            completedDays: [
                TestCalendar.date(2026, 8, 10),  // previous week
                TestCalendar.date(2026, 8, 24)   // next week
            ]
        )
        let row = slots(habit)

        // A fresh, empty row: the week rolls over with no carry-over.
        #expect(row.map(\.state) == [.open, .inactive, .inactive])
    }

    @Test("A habit edited down to fewer pills than it has completions clamps")
    func frequencyOverfilled() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [
                TestCalendar.date(2026, 8, 17),
                TestCalendar.date(2026, 8, 18),
                TestCalendar.date(2026, 8, 19)
            ]
        )
        let row = slots(habit)

        #expect(row.count == 2)
        #expect(row.allSatisfy { $0.state == .filled })
    }

    // MARK: - The invariant

    @Test("At most one slot per habit is ever open")
    func atMostOneOpenSlot() {
        let cadences: [Frequency] = [.daily, .timesPerWeek(2), .timesPerWeek(3),
                                     .timesPerWeek(4), .timesPerWeek(5), .timesPerWeek(6)]
        let weekDays = week.days

        for frequency in cadences {
            // Every subset of this week is a valid completion history.
            for mask in 0..<(1 << 7) {
                let completed = Set(weekDays.enumerated().compactMap { index, day in
                    mask & (1 << index) != 0 ? day : nil
                })
                let habit = HabitSnapshot.fixture(frequency: frequency, completedDays: completed)
                let open = slots(habit).filter { $0.state == .open }
                #expect(open.count <= 1, "\(frequency) with mask \(mask) produced \(open.count) open slots")
            }
        }
    }

    @Test("Every tappable slot acts on today and nothing else")
    func tapsOnlyEverTouchToday() {
        let cadences: [Frequency] = [.daily, .timesPerWeek(3), .timesPerWeek(6)]
        for frequency in cadences {
            for mask in 0..<(1 << 7) {
                let completed = Set(week.days.enumerated().compactMap { index, day in
                    mask & (1 << index) != 0 ? day : nil
                })
                let habit = HabitSnapshot.fixture(frequency: frequency, completedDays: completed)
                for slot in slots(habit) where slot.isTappable {
                    #expect(slot.actionDay == today)
                }
            }
        }
    }

    // MARK: - Which surface is editing

    @Test("The week view edits every day up to today, and the widget only today")
    func surfacesDifferInWhatTheyEdit() {
        let habit = HabitSnapshot.fixture()
        // Today is Wednesday, column 2.
        #expect(slots(habit, editing: .todayOnly).filter(\.isTappable).map(\.index) == [2])
        #expect(
            slots(habit, editing: .week(allowingFuture: false))
                .filter(\.isTappable).map(\.index) == [0, 1, 2]
        )
        #expect(
            slots(habit, editing: .week(allowingFuture: true))
                .filter(\.isTappable).map(\.index) == [0, 1, 2, 3, 4, 5, 6]
        )
    }

    @Test("A tappable past day acts on itself, not on today")
    func pastDaysActOnThemselves() {
        let row = slots(.fixture(), editing: .week(allowingFuture: false))
        for slot in row where slot.isTappable {
            #expect(slot.actionDay == week.days[slot.index])
        }
        // The whole point of the widening: a tap on Monday writes Monday.
        #expect(row[0].actionDay == TestCalendar.date(2026, 8, 17))
    }

    @Test("A completion on a past day still draws as a past completion")
    func editableDaysAreNotToday() {
        // `Slot.isToday` used to be an alias for "carries an action", which was
        // true only while today was the one day that did. Six more days carry
        // one now, and Monday's completion must still draw unlit-of-today's
        // mark rather than becoming today's.
        let habit = HabitSnapshot.fixture(completedDays: [TestCalendar.date(2026, 8, 17), today])
        let row = slots(habit, editing: .week(allowingFuture: false))

        #expect(row[0].isTappable)
        #expect(!row[0].isToday)
        #expect(row[0].mark == .donePast)
        #expect(row[2].isToday)
        #expect(row[2].mark == .doneToday)
    }

    @Test("The rest day is never editable, on any surface")
    func restDayIsNeverEditable() {
        // Monday is the rest day, and Monday is in the past — the column the
        // week view would otherwise now hand an action to.
        let monday = TestPreferences.weekday(ofColumn: 0, in: week, calendar: calendar)
        let cases: [SlotEditing] = [.todayOnly, .week(allowingFuture: false), .week(allowingFuture: true)]

        for editing in cases {
            let row = slots(.fixture(), editing: editing, restDay: monday)
            #expect(row[0].state == .rest)
            #expect(!row[0].isTappable, "\(editing) offered the rest day")
        }
    }

    @Test("Every history, every surface: what is tappable is exactly what that surface allows")
    func tappabilityOverEveryHistory() {
        // The exhaustive pass, now run under each surface's rule rather than
        // under the one rule there used to be.
        for mask in 0..<(1 << 7) {
            let completed = Set(week.days.enumerated().compactMap { index, day in
                mask & (1 << index) != 0 ? day : nil
            })
            let habit = HabitSnapshot.fixture(completedDays: completed)

            let todayOnly = slots(habit, editing: .todayOnly).filter(\.isTappable)
            #expect(todayOnly.count == 1, "mask \(mask) offered \(todayOnly.count) days on a widget")
            #expect(todayOnly.first?.actionDay == today)

            let past = slots(habit, editing: .week(allowingFuture: false)).filter(\.isTappable)
            #expect(past.map(\.index) == [0, 1, 2], "mask \(mask) reached the wrong days")

            let all = slots(habit, editing: .week(allowingFuture: true)).filter(\.isTappable)
            #expect(all.count == 7, "mask \(mask) withheld a day the demo allows")
            #expect(all.allSatisfy { $0.actionDay == week.days[$0.index] })
        }
    }

    @Test("A pill is not a day, so widening the surface does not widen a frequency row")
    func frequencyRowsIgnoreTheSurface() {
        // An N×/week row is not day-pinned: its pills stand for reps, not
        // weekdays, so there is no past day here for a surface to reach. The
        // day-shaped editing of these habits happens on the spans.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(4),
            completedDays: [TestCalendar.date(2026, 8, 17)]
        )
        for editing in [SlotEditing.todayOnly, .week(allowingFuture: true)] {
            let row = slots(habit, editing: editing)
            #expect(row.filter(\.isTappable).map(\.index) == [1])
            #expect(row.filter(\.isTappable).allSatisfy { $0.actionDay == today })
        }
    }

    // MARK: - An earlier week (#117)

    /// The week beginning Monday 2026-08-03, two weeks before this one — the
    /// branch that has no today in it at all.
    private var pastWeek: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 3), calendar: calendar)
    }

    private func pastSlots(_ habit: HabitSnapshot, editing: SlotEditing) -> [Slot] {
        WeekGrid.slots(
            for: habit, in: pastWeek, today: today, editing: editing,
            restDay: nil, calendar: calendar
        )
    }

    @Test("Every history of an earlier week: the week view reaches all seven days")
    func pastWeekTappabilityOverEveryHistory() {
        // The same exhaustive pass, on the week the issue makes load-bearing.
        // A week with no today in it used to be a branch nothing tapped; it is
        // now every week but one.
        for mask in 0..<(1 << 7) {
            let completed = Set(pastWeek.days.enumerated().compactMap { index, day in
                mask & (1 << index) != 0 ? day : nil
            })
            let habit = HabitSnapshot.fixture(completedDays: completed)

            // R1 holds: nothing is open in a week that is over, on any surface.
            for editing in [SlotEditing.todayOnly, .week(allowingFuture: false),
                            .week(allowingFuture: true)] {
                let row = pastSlots(habit, editing: editing)
                #expect(row.count == 7, "mask \(mask) drew \(row.count) slots")
                #expect(!row.contains { $0.state == .open }, "mask \(mask) opened a past day")
                #expect(!row.contains { $0.isToday }, "mask \(mask) called a past day today")
            }

            // R2 as the difference between the surfaces, exactly as the
            // current week asserts it.
            #expect(pastSlots(habit, editing: .todayOnly).allSatisfy { !$0.isTappable })

            for editing in [SlotEditing.week(allowingFuture: false), .week(allowingFuture: true)] {
                let row = pastSlots(habit, editing: editing)
                #expect(
                    row.allSatisfy { $0.isTappable },
                    "mask \(mask) withheld a day of \(editing)"
                )
                #expect(row.allSatisfy { $0.actionDay == pastWeek.days[$0.index] })
            }

            // Every day is filled or missed — there is no third thing a day
            // that has been and gone can be.
            let states = pastSlots(habit, editing: .week(allowingFuture: false)).map(\.state)
            #expect(states.allSatisfy { $0 == .filled || $0 == .missed }, "mask \(mask)")
            #expect(states.count { $0 == .filled } == completed.count, "mask \(mask)")
        }
    }

    @Test("A completion in an earlier week draws as a past completion, never as today's")
    func pastWeekCompletionsAreNotToday() {
        let habit = HabitSnapshot.fixture(completedDays: [pastWeek.days[1]])
        let row = pastSlots(habit, editing: .week(allowingFuture: false))

        #expect(row[1].state == .filled)
        #expect(row[1].mark == .donePast)
        #expect(row[0].mark == .missed)
    }

    @Test("A day outside the displayed week leaves no slot open")
    func todayOutsideTheWeek() {
        let otherWeek = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 10), calendar: calendar)
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(3))
        let row = WeekGrid.slots(
            for: habit, in: otherWeek, today: today, editing: .todayOnly,
            restDay: nil, calendar: calendar
        )

        #expect(row.allSatisfy { $0.state != .open })
        #expect(row.allSatisfy { !$0.isTappable })
    }
}
