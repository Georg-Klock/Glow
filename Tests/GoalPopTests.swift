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

    private func met(_ h: HabitSnapshot) -> Bool {
        GoalMet.justMet(habit: h, in: week)
    }

    // MARK: - The goal, not each repetition

    @Test("A completion past the goal fires nothing")
    func pastTheGoalIsSilent() {
        // Exactly met, not met-or-past — which is also what removes the need to
        // know what the count was before the write.
        #expect(!met(habit(.timesPerWeek(2), counts: [0: 1, 1: 1, 2: 1])))
        #expect(!met(habit(.timesPerWeek(1), counts: [0: 1, 3: 1])))
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
        #expect(!GoalMet.justMet(habit: habit, in: week))
    }

    @Test("A blank row has no goal to meet")
    func spacersHaveNoGoal() {
        let spacer = HabitSnapshot(
            id: UUID(), name: "", icon: "", frequency: .daily,
            completionCounts: [:], isSpacer: true
        )
        #expect(!GoalMet.justMet(habit: spacer, in: week))
    }

    @Test("Every cadence has a goal, and it is the number the habit asks for")
    func targets() {
        #expect(GoalMet.target(of: .daily) == Frequency.daysInWeek)
        #expect(GoalMet.target(of: .timesPerWeek(4)) == 4)
    }

    // MARK: - The line

    @Test("The same completion always says the same thing", arguments: [GoalPop.Register.logged, .goal])
    func lineIsStable(register: GoalPop.Register) {
        // A Live Activity's content can be re-read, and a phrase that changed
        // under the reader would look like a glitch.
        let id = UUID()
        let first = GoalPop.line(habitID: id, on: day(4), register: register, calendar: calendar)
        for _ in 0..<50 {
            #expect(
                GoalPop.line(habitID: id, on: day(4), register: register, calendar: calendar)
                    == first
            )
        }
        #expect(GoalPop.lines(for: register).contains(first))
    }

    @Test("Each vocabulary is short, clean and fully reachable", arguments: [GoalPop.Register.logged, .goal])
    func vocabulary(register: GoalPop.Register) {
        let vocabulary = GoalPop.lines(for: register)
        #expect(!vocabulary.isEmpty)
        // Short is a hard constraint: a compact Island state truncates rather
        // than wraps.
        #expect(vocabulary.allSatisfy { $0.count <= 16 })
        #expect(vocabulary.allSatisfy { !$0.isEmpty })
        // Every line is reachable — a hash that collapsed onto one would make
        // the set a lie.
        var seen = Set<String>()
        for i in 0..<400 {
            seen.insert(GoalPop.line(
                habitID: UUID(), on: day(i % 7), register: register, calendar: calendar
            ))
        }
        #expect(seen.count == vocabulary.count)
    }

    // MARK: - The switch

    @Test("Default is everything, which an AppStorage default would have got wrong")
    func defaultIsOn() {
        let previous = GlowSettings.store.object(forKey: PopPreferences.key)
        defer { GlowSettings.store.set(previous, forKey: PopPreferences.key) }

        // The trap the sentinel exists for: a key nobody has written must read
        // as *on*, and `@AppStorage`'s own default would hand back 0. #185 made
        // it `everything` rather than `goals` — people need encouragement, and
        // a fresh install has no stored setting to protect.
        GlowSettings.store.removeObject(forKey: PopPreferences.key)
        #expect(PopPreferences.isEnabled)
        #expect(PopPreferences.level == .everything)

        PopPreferences.level = .off
        #expect(!PopPreferences.isEnabled)
        #expect(
            GlowSettings.store.object(forKey: PopPreferences.key) as? Int
                == PopPreferences.Level.off.rawValue
        )

        PopPreferences.level = .goals
        #expect(PopPreferences.isEnabled)
    }

    @Test("Nobody's stored setting changes meaning")
    func storedOnStillMeansGoals() {
        // "On" was 1 before there were three levels, and 1 is `goals` now — so
        // an install that already turned this on keeps exactly what it had,
        // rather than being upgraded into being spoken to on every tap (#119).
        let previous = GlowSettings.store.object(forKey: PopPreferences.key)
        defer { GlowSettings.store.set(previous, forKey: PopPreferences.key) }

        GlowSettings.store.set(1, forKey: PopPreferences.key)
        #expect(PopPreferences.level == .goals)
        GlowSettings.store.set(2, forKey: PopPreferences.key)
        #expect(PopPreferences.level == .off)
    }

    @Test("Each level allows exactly what it says")
    func levelsAllowTheRightRegisters() {
        #expect(!PopPreferences.allows(.logged, at: .off))
        #expect(!PopPreferences.allows(.goal, at: .off))

        #expect(!PopPreferences.allows(.logged, at: .goals))
        #expect(PopPreferences.allows(.goal, at: .goals))

        #expect(PopPreferences.allows(.logged, at: .everything))
        #expect(PopPreferences.allows(.goal, at: .everything))

        // Unset is everything, everywhere it is asked (#185).
        #expect(PopPreferences.allows(.logged, at: .unset))
        #expect(PopPreferences.allows(.goal, at: .unset))
    }

    // MARK: - Two vocabularies

    @Test("The routine line and the goal's are different words")
    func vocabulariesDoNotOverlap() {
        // The whole reason there are two: sharing a list would make the goal
        // indistinguishable from the twelfth glass of water, which is what the
        // old restriction was really guarding against.
        #expect(Set(GoalPop.lines).isDisjoint(with: Set(GoalPop.goalLines)))
        #expect(!GoalPop.lines.isEmpty)
        #expect(!GoalPop.goalLines.isEmpty)
    }

    @Test("Both vocabularies fit a compact Island state")
    func linesStayShort() {
        // Not a style preference: anything that does not fit is truncated by
        // the system rather than wrapped.
        for line in GoalPop.lines + GoalPop.goalLines {
            #expect(line.count <= 16, "\(line) is \(line.count) characters")
            #expect(line == line.lowercased(), "\(line) is not in the app's voice")
        }
    }

    @Test("The pair for one tap reads as one moment")
    func registersShareASeed() {
        // Same index, different list — so the routine line and the goal line a
        // single tap produces are the same *position* in two vocabularies
        // rather than two unrelated phrases.
        let id = UUID()
        for i in 0..<7 {
            let routine = GoalPop.line(habitID: id, on: day(i), register: .logged, calendar: calendar)
            let goal = GoalPop.line(habitID: id, on: day(i), register: .goal, calendar: calendar)
            let a = GoalPop.lines.firstIndex(of: routine)
            let b = GoalPop.goalLines.firstIndex(of: goal)
            #expect(a == b)
        }
    }
}

/// #102: two goals met inside one pop's two seconds.
@Suite("Pop window")
struct PopWindowTests {
    @Test("Only the newest pop may end the activity")
    func newestWins() {
        // One shared activity means one shared ending, and the first tap's
        // timer must not close a pop the second goal has just refreshed.
        #expect(PopWindow.shouldEnd(scheduled: 2, latest: 2))
        #expect(!PopWindow.shouldEnd(scheduled: 1, latest: 2))
    }

    @Test("A pop nobody replaced still ends")
    func aloneStillEnds() {
        // The ordinary case, and the one that would go wrong if the guard were
        // written the other way round: a single pop has to close itself, or it
        // sits on the Lock Screen until the system times it out.
        #expect(PopWindow.shouldEnd(scheduled: 1, latest: 1))
        #expect(PopWindow.shouldEnd(scheduled: 9, latest: 9))
    }

    @Test("A stale number never closes a later pop")
    func staleNeverCloses() {
        // Three goals in a flurry: only the third's ending counts, whatever
        // order the sleeping tasks wake in.
        #expect(!PopWindow.shouldEnd(scheduled: 1, latest: 3))
        #expect(!PopWindow.shouldEnd(scheduled: 2, latest: 3))
        #expect(PopWindow.shouldEnd(scheduled: 3, latest: 3))
    }
}


/// #273: the app pops too, so both surfaces decide *what* to say in one place.
@Suite("The pop's registers")
struct PopRegisterTests {
    @Test("A routine log says one thing; the tap that meets the goal says two")
    func registersFollowTheGoal() {
        #expect(GoalPop.registers(justMetGoal: false) == [.logged])
        #expect(GoalPop.registers(justMetGoal: true) == [.logged, .goal])
    }

    /// The order is the sequence both surfaces play: the routine line first,
    /// then the goal's after `GoalPop.handover`. Reversing it would say "you
    /// did it" and then take it back to "logged".
    @Test("The goal's line comes second, never first")
    func theGoalLineIsSecond() {
        let both = GoalPop.registers(justMetGoal: true)
        #expect(both.first == .logged)
        #expect(both.last == .goal)
    }

    /// Preferences filter the list rather than changing it, which is what lets
    /// "Goals" show the goal line alone — the second register surviving when
    /// the first does not is the case that would break a sequence built as
    /// "first, then maybe second".
    @Test("Goals-only leaves the goal line and drops the routine one")
    func goalsOnlyKeepsTheSecond() {
        let both = GoalPop.registers(justMetGoal: true)
        #expect(both.filter { PopPreferences.allows($0, at: .goals) } == [.goal])
        let routine = GoalPop.registers(justMetGoal: false)
        #expect(routine.filter { PopPreferences.allows($0, at: .goals) }.isEmpty)
    }

    @Test("Off drops both, everything keeps both")
    func theOtherTwoLevels() {
        let both = GoalPop.registers(justMetGoal: true)
        #expect(both.filter { PopPreferences.allows($0, at: .off) }.isEmpty)
        #expect(both.filter { PopPreferences.allows($0, at: .everything) } == [.logged, .goal])
    }
}
