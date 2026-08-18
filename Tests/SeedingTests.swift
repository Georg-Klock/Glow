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

    @Test("Nothing is pre-completed")
    func seedsNoHistory() throws {
        // The whole signal of the app is that today's slot is unfinished.
        // Seeding a completion would be inventing behaviour the user never had.
        let context = try makeContext()
        try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            #expect(habit.completedDays.isEmpty)
        }
    }

    @Test("Every seeded habit is open today and nothing else is filled")
    func seededHabitsAreOpenToday() throws {
        let context = try makeContext()
        try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        let week = WeekCalendar.week(containing: today, calendar: calendar)
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            let slots = WeekGrid.slots(for: habit.snapshot(), in: week, today: today, calendar: calendar)
            #expect(slots.filter { $0.state == .open }.count == 1)
            #expect(slots.allSatisfy { $0.state != .filled })
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
