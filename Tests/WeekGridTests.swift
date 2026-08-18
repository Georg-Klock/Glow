import Foundation
import Testing
@testable import Glow

@Suite("Slot states")
struct WeekGridTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    private func slots(_ habit: HabitSnapshot) -> [Slot] {
        WeekGrid.slots(for: habit, in: week, today: today, calendar: calendar)
    }

    // MARK: - Daily

    @Test("A daily habit shows exactly seven circles")
    func dailyRowHasSevenSlots() {
        #expect(slots(.fixture()).count == 7)
    }

    @Test("Today's circle is open, past days are inactive, future days are inactive")
    func dailyStates() {
        let row = slots(.fixture())

        #expect(row[0].state == .inactive)  // Monday, missed
        #expect(row[1].state == .inactive)  // Tuesday, missed
        #expect(row[2].state == .open)      // Wednesday, today
        #expect(row[3].state == .inactive)  // Thursday, not yet
        #expect(row[6].state == .inactive)
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

    @Test("A day outside the displayed week leaves no slot open")
    func todayOutsideTheWeek() {
        let otherWeek = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 10), calendar: calendar)
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(3))
        let row = WeekGrid.slots(for: habit, in: otherWeek, today: today, calendar: calendar)

        #expect(row.allSatisfy { $0.state != .open })
        #expect(row.allSatisfy { !$0.isTappable })
    }
}
