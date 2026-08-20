import Foundation
import SwiftData
import Testing
@testable import Glow

@Suite("Default habits")
@MainActor
struct SeedingTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A throwaway defaults domain per test, so one test's "already seeded"
    /// flag cannot decide another's outcome, and so a run never touches the
    /// real one.
    private func makeDefaults() -> UserDefaults {
        let suite = "seeding-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func seeder(_ context: ModelContext, _ defaults: UserDefaults) -> HabitSeeder {
        HabitSeeder(context: context, defaults: defaults, calendar: calendar)
    }

    @Test("A fresh install starts with the default habits")
    func seedsOnFirstLaunch() throws {
        let context = try makeContext()
        let added = try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        #expect(added == DefaultHabits.all.count)
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(habits.map(\.name) == DefaultHabits.all.map(\.name))
        #expect(habits.map(\.frequency) == DefaultHabits.all.map(\.frequency))
    }

    @Test("A past is seeded, and today is never part of it")
    func seedsHistoryButNotToday() throws {
        // The reverse of what this asserted until 2026-08-20. The history is
        // invented — SeededHistory says so and says how to switch it off — but
        // today staying empty is not negotiable: the open slot is the one thing
        // the app is for, and a seed that filled it would hide the feature on
        // the first screen anyone sees.
        let context = try makeContext()
        try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        #expect(try context.fetchCount(FetchDescriptor<Completion>()) > 0)
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            #expect(!habit.completedDays.isEmpty, "\(habit.name) has no history")
            #expect(!habit.completedDays.contains(today), "\(habit.name) was pre-completed today")
        }
    }

    @Test("Every seeded habit is open today")
    func seededHabitsAreOpenToday() throws {
        let context = try makeContext()
        try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        let week = WeekCalendar.week(containing: today, calendar: calendar)
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            let slots = WeekGrid.slots(for: habit.snapshot(), in: week, today: today, calendar: calendar)
            #expect(slots.filter { $0.state == .open }.count == 1, "\(habit.name)")
        }
    }

    @Test("The seeded past is the same on every install")
    func historyIsDeterministic() throws {
        // A system generator would make each install different, which defeats
        // the point: this is demo content, the tests assert against it, and
        // "it looked different on my phone" should not be possible.
        func seed() throws -> [String: Set<Date>] {
            let context = try makeContext()
            try seeder(context, makeDefaults()).seedIfNeeded(now: today)
            var result: [String: Set<Date>] = [:]
            for habit in try context.fetch(FetchDescriptor<Habit>()) {
                result["\(habit.name) \(habit.frequency)"] = habit.completedDays
            }
            return result
        }
        #expect(try seed() == seed())
    }

    @Test("A perfect habit really is perfect, and an uneven one is not")
    func formsProduceTheirRates() throws {
        // The point of the seed is that a full streak is visible and a missed
        // day is visible. If every habit came out the same these would be eight
        // rows of identical noise.
        let perfect = SeededHistory.completions(
            for: .daily, form: .perfect, seed: 1, today: today, calendar: calendar
        )
        let uneven = SeededHistory.completions(
            for: .daily, form: .uneven, seed: 1, today: today, calendar: calendar
        )
        #expect(perfect.count > uneven.count)

        // Perfect means every day back to the start, with none skipped.
        let days = Set(perfect)
        var cursor = perfect.min() ?? today
        while cursor < today {
            #expect(days.contains(cursor), "perfect run has a hole at \(cursor)")
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today
        }
    }

    @Test("An N-times-a-week habit is seeded by the week, not by the day")
    func frequencyHistoryRespectsTheGoal() throws {
        // Seeded per day, a 2x-a-week habit lands six completions in one week
        // and none in the next, and every row reads as broken.
        let days = SeededHistory.completions(
            for: .timesPerWeek(2), form: .perfect, seed: 5, today: today, calendar: calendar
        )
        let byWeek = Dictionary(grouping: days) {
            WeekCalendar.startOfWeek(containing: $0, calendar: calendar)
        }
        // The current week is partial, so only the whole ones are checked.
        let thisWeek = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        for (start, completions) in byWeek where start != thisWeek {
            #expect(completions.count == 2, "week of \(start) has \(completions.count)")
        }
    }

    @Test("Seeding runs once, not on every launch")
    func seedsOnlyOnce() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == DefaultHabits.all.count)
        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
    }

    @Test("Deleting every habit does not bring them back")
    func doesNotReseedAfterDeletion() throws {
        // "Is the store empty" and "has this install been seeded" are different
        // questions, and answering the second with the first makes the app
        // impossible to empty.
        let context = try makeContext()
        let defaults = makeDefaults()
        try seeder(context, defaults).seedIfNeeded(now: today)

        let store = HabitStore(context: context, calendar: calendar)
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            try store.delete(habit)
        }

        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == 0)
    }

    @Test("An install that already has habits is left alone")
    func doesNotSeedOverExistingHabits() throws {
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar)
        try store.addHabit(name: "Mine", icon: "star", frequency: .daily)

        #expect(try seeder(context, makeDefaults()).seedIfNeeded(now: today) == 0)
        let habits = try context.fetch(FetchDescriptor<Habit>())
        #expect(habits.map(\.name) == ["Mine"])
    }

    @Test("Every default habit uses a symbol the picker can draw")
    func defaultsUseRealSymbols() {
        // A seeded habit whose icon is not in the catalogue would render as
        // literal text, which is how a typo here would reach a first launch.
        for template in DefaultHabits.all {
            #expect(HabitSymbol.isSymbol(template.icon), "\(template.icon) is not a known symbol")
        }
    }

    @Test("The defaults show both row shapes")
    func defaultsCoverBothCadences() {
        let cadences = Set(DefaultHabits.all.map(\.frequency))
        #expect(cadences.contains(.daily))
        #expect(cadences.contains { if case .timesPerWeek = $0 { true } else { false } })
    }
}
