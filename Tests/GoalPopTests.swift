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

    @Test("One habit on one day does not keep saying the same thing")
    func theLineIsDrawnFresh() {
        // The defect #450 was filed for: the line was hashed from the habit
        // and the day, so one habit said exactly one thing all day however
        // many times it was toggled. Over 200 draws from what used to be a
        // fixed seed, more than one phrase has to appear. With 173 phrases the
        // chance of a false failure is (1/173)^199.
        var seen = Set<String>()
        for _ in 0..<200 {
            seen.insert(GoalPop.line())
        }
        #expect(seen.count > 1, "the pop repeats: every draw said the same thing")
    }

    @Test("Every line drawn is one of the pool's")
    func theLineComesFromThePool() {
        for _ in 0..<200 {
            #expect(GoalPop.lines.contains(GoalPop.line()))
        }
    }

    @Test("Every line in the pool is reachable")
    func everyLineIsReachable() {
        // A draw that could not reach part of the list would make the count a
        // lie. 20,000 draws over 173 phrases leaves the chance of missing any
        // one of them at e^-115 — an argument that is more true of a real
        // random draw than it was of the hash it replaced.
        var seen = Set<String>()
        for _ in 0..<20_000 {
            seen.insert(GoalPop.line())
        }
        #expect(seen.count == GoalPop.lines.count)
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
    func levelsAllowTheRightTaps() {
        // The switch is unchanged by #420 — it never depended on the two
        // vocabularies, only on whether this tap met the goal.
        #expect(!PopPreferences.allows(justMetGoal: false, at: .off))
        #expect(!PopPreferences.allows(justMetGoal: true, at: .off))

        #expect(!PopPreferences.allows(justMetGoal: false, at: .goals))
        #expect(PopPreferences.allows(justMetGoal: true, at: .goals))

        #expect(PopPreferences.allows(justMetGoal: false, at: .everything))
        #expect(PopPreferences.allows(justMetGoal: true, at: .everything))

        // Unset is everything, everywhere it is asked (#185).
        #expect(PopPreferences.allows(justMetGoal: false, at: .unset))
        #expect(PopPreferences.allows(justMetGoal: true, at: .unset))
    }

    @Test("Goals is the only level that reads the goal at all")
    func onlyGoalsDependsOnTheTap() {
        // Off and Everything answer the same for both taps; Goals is where the
        // boolean does any work. Written as the shape rather than the values,
        // because it is the shape that "Never / Goals / Everything" means.
        for level in [PopPreferences.Level.off, .everything, .unset] {
            #expect(
                PopPreferences.allows(justMetGoal: true, at: level)
                    == PopPreferences.allows(justMetGoal: false, at: level),
                "\(level) should not care whether the tap met the goal"
            )
        }
        #expect(
            PopPreferences.allows(justMetGoal: true, at: .goals)
                != PopPreferences.allows(justMetGoal: false, at: .goals)
        )
    }

    // MARK: - The pool

    @Test("The pool is 173 phrases with no duplicates")
    func thePoolIsWhatItSaysItIs() {
        // The count is the point of #420: six phrases were exhausted inside a
        // week by anybody logging twice a day. A duplicate would quietly make
        // one phrase twice as likely and the pool one shorter than it reads.
        #expect(GoalPop.lines.count == 173)
        #expect(Set(GoalPop.lines).count == GoalPop.lines.count)
    }

    @Test("Every line fits the compact Island without leaning on the scale floor")
    func linesStayShort() {
        // Not a style preference. #310 measured the compact trailing region
        // against "that's the week" and found it cannot carry fifteen
        // characters at any pushed size — that line survived only on
        // `minimumScaleFactor(0.6)`. Fourteen is the budget, and this is the
        // guard against the next batch of phrases putting the problem back.
        #expect(GoalPop.maximumLineLength == 14)
        for line in GoalPop.lines {
            #expect(
                line.count <= GoalPop.maximumLineLength,
                "\(line) is \(line.count) characters"
            )
            #expect(!line.isEmpty)
        }
    }

    @Test("Every line is in the app's voice")
    func linesAreLowercase() {
        for line in GoalPop.lines {
            #expect(line == line.lowercased(), "\(line) is not in the app's voice")
            #expect(
                line.trimmingCharacters(in: .whitespaces) == line,
                "\(line) has whitespace at an end"
            )
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


/// #420: one tap, one pop. The double-fire this replaced was the only one in
/// the app, and it lived at two call sites rather than in a type — so this is
/// where the removal is held.
@Suite("One pop per tap")
struct OnePopPerTapTests {
    /// **The load-bearing part is that `allows` returns one answer.**
    ///
    /// It used to return a *sequence*: `GoalPop.registers(justMetGoal:)` handed
    /// back `[.logged, .goal]` for the tap that met the goal, and both call
    /// sites played it — pop, sleep `GoalPop.handover`, pop again. A `Bool`
    /// cannot express two pops, so the shape of the API is the guard, and this
    /// test says so out loud rather than trusting the signature to stay.
    @Test("The switch answers one tap with one verdict")
    func theVerdictIsOneAnswer() {
        let verdict: Bool = PopPreferences.allows(justMetGoal: true, at: .everything)
        #expect(verdict)
        // And the goal-completing tap draws from the same pool as any other:
        // there is no second list for it to reach.
        #expect(GoalPop.lines.contains(GoalPop.line()))
    }

    /// The two call sites are a `@MainActor` view and an ActivityKit wrapper,
    /// so neither can be driven from here. What can be checked is that neither
    /// still schedules a *second* thing to say: a handover needs a sleep, and
    /// the only sleep either file is allowed is the one that ends the pop.
    ///
    /// A source scan for the same reason `WidgetPlacementTests` uses them —
    /// the behaviour is in code no test in this process reaches.
    @Test("Neither call site sleeps for anything but the pop's own end")
    func noCallSiteSchedulesASecondLine() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sites = [
            root.appendingPathComponent("Glow/Store/GoalPopCentre.swift"),
            root.appendingPathComponent("Glow/Views/WeeklyGridView.swift"),
        ]

        var sleeps = 0
        for file in sites {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.isEmpty, "\(file.lastPathComponent) is empty")
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let code = line.trimmingCharacters(in: .whitespaces)
                // The doc comments in both files describe the handover that was
                // removed, which is the point of keeping them.
                guard !code.hasPrefix("//") && !code.hasPrefix("///") else { continue }
                guard code.contains("Task.sleep(for:") else { continue }
                sleeps += 1
                #expect(
                    code.contains("GoalPop.duration"),
                    """
                    \(file.lastPathComponent) sleeps for something other than \
                    GoalPop.duration; a second line inside one pop's window is \
                    the double-fire #420 removed: \(code)
                    """
                )
            }
        }
        // One end per call site. A scan that matched nothing would pass while
        // saying nothing.
        #expect(sleeps == 2, "the pop-sleep scan matched \(sleeps) calls, expected 2")
    }

    /// Preferences gate the pop rather than selecting words, which is the whole
    /// of what the register was doing that anybody wanted.
    @Test("Goals speaks for the goal-completing tap and for nothing else")
    func goalsOnlySpeaksOnce() {
        #expect(PopPreferences.allows(justMetGoal: true, at: .goals))
        #expect(!PopPreferences.allows(justMetGoal: false, at: .goals))
    }

    @Test("Off says nothing, everything says one thing either way")
    func theOtherTwoLevels() {
        #expect(!PopPreferences.allows(justMetGoal: true, at: .off))
        #expect(!PopPreferences.allows(justMetGoal: false, at: .off))
        #expect(PopPreferences.allows(justMetGoal: true, at: .everything))
        #expect(PopPreferences.allows(justMetGoal: false, at: .everything))
    }
}
