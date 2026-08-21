import Foundation
import SwiftData
import Testing
@testable import Glow

/// The demo-history toggle's contract: an invented past that goes in on
/// request and comes back out exactly, leaving everything the user logged.
@Suite("Demo history")
@MainActor
struct DemoHistoryTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "demo-history-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A store with the default habits and nothing logged.
    private func seededContext(_ defaults: UserDefaults) throws -> ModelContext {
        let context = try makeContext()
        try HabitSeeder(context: context, defaults: defaults, calendar: calendar)
            .seedIfNeeded(now: today)
        return context
    }

    private func demo(_ context: ModelContext, _ defaults: UserDefaults) -> DemoHistory {
        DemoHistory(context: context, defaults: defaults, calendar: calendar)
    }

    @Test("Seeding fills a past for every real habit, and today is never part of it")
    func seedsEveryHabitButNotToday() throws {
        let defaults = makeDefaults()
        let context = try seededContext(defaults)
        let demo = demo(context, defaults)

        #expect(!demo.isSeeded)
        try demo.seed(now: today)
        #expect(demo.isSeeded)

        for habit in try context.fetch(FetchDescriptor<Habit>()) where !habit.isSpacer {
            #expect(!habit.completedDays.isEmpty, "\(habit.name) has no history")
            #expect(!habit.completedDays.contains(today), "\(habit.name) was pre-completed today")
        }
    }

    @Test("Removal takes out exactly what seeding added")
    func removalIsExact() throws {
        let defaults = makeDefaults()
        let context = try seededContext(defaults)
        let demo = demo(context, defaults)
        try demo.seed(now: today)

        try demo.remove()
        #expect(!demo.isSeeded)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
    }

    @Test("A completion the user logged survives the demo coming out")
    func userDataSurvives() throws {
        let defaults = makeDefaults()
        let context = try seededContext(defaults)
        let store = HabitStore(context: context, calendar: calendar)
        let demo = demo(context, defaults)
        try demo.seed(now: today)

        // Logged by hand while the demo is in — including on a day the demo
        // also filled, which is exactly where an inexact removal would eat it.
        let habit = try #require(
            try context.fetch(FetchDescriptor<Habit>()).first { !$0.isSpacer }
        )
        let yesterday = TestCalendar.date(2026, 8, 18)
        try store.addCompletion(for: habit, on: yesterday)
        try store.addCompletion(for: habit, on: today)

        try demo.remove()
        #expect(store.count(for: habit, on: yesterday) == 1)
        #expect(store.count(for: habit, on: today) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 2)
    }

    @Test("Seeding twice is one demo, not two stacked")
    func seedIsIdempotent() throws {
        let defaults = makeDefaults()
        let context = try seededContext(defaults)
        let demo = demo(context, defaults)

        try demo.seed(now: today)
        let first = try context.fetchCount(FetchDescriptor<Completion>())
        try demo.seed(now: today)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == first)
    }

    @Test("Off and on again rebuilds the same past")
    func reseedIsDeterministic() throws {
        let defaults = makeDefaults()
        let context = try seededContext(defaults)
        let demo = demo(context, defaults)

        func snapshot() throws -> [String: [Date: Int]] {
            var result: [String: [Date: Int]] = [:]
            for habit in try context.fetch(FetchDescriptor<Habit>()) where !habit.isSpacer {
                result["\(habit.name) \(habit.frequency)"] = habit.completionCounts
            }
            return result
        }

        try demo.seed(now: today)
        let first = try snapshot()
        try demo.remove()
        try demo.seed(now: today)
        #expect(try snapshot() == first)
    }

    @Test("A per-day habit's demo never overshoots its target")
    func perDayStaysWithinTarget() throws {
        let defaults = makeDefaults()
        let context = try seededContext(defaults)
        let store = HabitStore(context: context, calendar: calendar)
        let habit = try store.addHabit(
            name: "Water", icon: "drop", frequency: Frequency(timesPerDay: 3), now: today
        )

        try demo(context, defaults).seed(now: today)

        for (day, count) in habit.completionCounts {
            #expect(count <= 3, "\(day) holds \(count) of 3")
            #expect(day != today)
        }
        #expect(!habit.completionCounts.isEmpty)
    }

    @Test("The first habit's demo past is perfect, so a full streak is on screen")
    func firstHabitIsPerfect() throws {
        // Position, not identity: SeededHistory.form(at: 0) is .perfect, and
        // the seeder's first habit is daily, so every past day is filled.
        #expect(SeededHistory.form(at: 0) == .perfect)

        let defaults = makeDefaults()
        let context = try seededContext(defaults)
        try demo(context, defaults).seed(now: today)

        let first = try #require(
            try context.fetch(
                FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
            ).first { !$0.isSpacer }
        )
        var day = try #require(first.completedDays.min())
        while day < today {
            let isRest = WeekPreferences.isRestDay(day, calendar: calendar)
            #expect(isRest || first.completedDays.contains(day), "hole at \(day)")
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
        }
    }
}
