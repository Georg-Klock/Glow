import Foundation
import Testing
@testable import Glow

/// #58: the goal, not each repetition — and the switch that is on by default.
@Suite("Goal pop", .serialized)
struct GoalPopTests {
    private let calendar = TestCalendar.monday
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }
    private func day(_ column: Int) -> Date { week.days[column] }

    private func habit(_ frequency: Frequency, counts: [Int: Int]) -> HabitSnapshot {
        HabitSnapshot(
            id: UUID(), name: "Water", icon: "drop", frequency: frequency,
            completionCounts: Dictionary(
                uniqueKeysWithValues: counts.map { (day($0.key), $0.value) }
            )
        )
    }

    private func met(_ h: HabitSnapshot, todayColumn: Int = 4) -> Bool {
        GoalMet.justMet(habit: h, in: week, today: day(todayColumn), calendar: calendar)
    }

    // MARK: - The goal, not each repetition

    @Test("A per-day habit fires on the last repetition and no other")
    func perDayFiresOnce() {
        // The twelfth glass, not each of the twelve.
        for count in 0..<12 {
            #expect(!met(habit(.timesPerDay(12), counts: [4: count])),
                    "fired at \(count) of 12")
        }
        #expect(met(habit(.timesPerDay(12), counts: [4: 12])))
    }

    @Test("A completion past the goal fires nothing")
    func pastTheGoalIsSilent() {
        // Exactly met, not met-or-past — which is also what removes the need to
        // know what the count was before the write.
        #expect(!met(habit(.timesPerDay(3), counts: [4: 4])))
        #expect(!met(habit(.timesPerWeek(2), counts: [0: 1, 1: 1, 2: 1])))
    }

    @Test("A weekly habit fires when the week's goal is met")
    func weeklyFiresOnTheGoal() {
        #expect(!met(habit(.timesPerWeek(3), counts: [0: 1, 1: 1])))
        #expect(met(habit(.timesPerWeek(3), counts: [0: 1, 1: 1, 2: 1])))
    }

    @Test("A daily habit's goal is a perfect week")
    func dailyIsSevenDays() {
        let six = Dictionary(uniqueKeysWithValues: (0..<6).map { ($0, 1) })
        #expect(!met(habit(.daily, counts: six)))
        let seven = Dictionary(uniqueKeysWithValues: (0..<7).map { ($0, 1) })
        #expect(met(habit(.daily, counts: seven)))
    }

    @Test("Completions in another week do not meet this week's goal")
    func otherWeeksDoNotCount() {
        let habit = HabitSnapshot(
            id: UUID(), name: "Run", icon: "figure.run",
            frequency: .timesPerWeek(2),
            completionCounts: [TestCalendar.date(2026, 8, 10): 1, day(0): 1]
        )
        #expect(!GoalMet.justMet(habit: habit, in: week, today: day(4), calendar: calendar))
    }

    @Test("A blank row has no goal to meet")
    func spacersHaveNoGoal() {
        let spacer = HabitSnapshot(
            id: UUID(), name: "", icon: "", frequency: .daily,
            completionCounts: [:], isSpacer: true
        )
        #expect(!GoalMet.justMet(habit: spacer, in: week, today: day(4), calendar: calendar))
    }

    @Test("Every cadence has a goal, and it is the number the habit asks for")
    func targets() {
        #expect(GoalMet.target(of: .daily) == Frequency.daysInWeek)
        #expect(GoalMet.target(of: .timesPerWeek(4)) == 4)
        #expect(GoalMet.target(of: .timesPerDay(12)) == 12)
    }

    // MARK: - The line

    @Test("The same completion always says the same thing")
    func lineIsStable() {
        // A Live Activity's content can be re-read, and a phrase that changed
        // under the reader would look like a glitch.
        let id = UUID()
        let first = GoalPop.line(habitID: id, on: day(4), calendar: calendar)
        for _ in 0..<50 {
            #expect(GoalPop.line(habitID: id, on: day(4), calendar: calendar) == first)
        }
        #expect(GoalPop.lines.contains(first))
    }

    @Test("The vocabulary is short, clean and non-empty")
    func vocabulary() {
        #expect(!GoalPop.lines.isEmpty)
        // Short is a hard constraint: a compact Island state truncates rather
        // than wraps.
        #expect(GoalPop.lines.allSatisfy { $0.count <= 16 })
        #expect(GoalPop.lines.allSatisfy { !$0.isEmpty })
        // Every line is reachable — a hash that collapsed onto one would make
        // the set a lie.
        var seen = Set<String>()
        for i in 0..<400 {
            seen.insert(GoalPop.line(
                habitID: UUID(), on: day(i % 7), calendar: calendar
            ))
        }
        #expect(seen.count == GoalPop.lines.count)
    }

    // MARK: - The switch

    @Test("Default on, which an AppStorage default would have got wrong")
    func defaultIsOn() {
        let previous = GlowSettings.store.object(forKey: PopPreferences.key)
        defer { GlowSettings.store.set(previous, forKey: PopPreferences.key) }

        // The trap the sentinel exists for: a key nobody has written must read
        // as *on*, and `@AppStorage`'s own default would hand back false.
        GlowSettings.store.removeObject(forKey: PopPreferences.key)
        #expect(PopPreferences.isEnabled)

        PopPreferences.isEnabled = false
        #expect(!PopPreferences.isEnabled)
        #expect(GlowSettings.store.object(forKey: PopPreferences.key) as? Int == PopPreferences.off)

        PopPreferences.isEnabled = true
        #expect(PopPreferences.isEnabled)
    }
}
