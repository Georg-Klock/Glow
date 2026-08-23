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

    /// A store with the default habits and nothing logged. Filled the way the
    /// app fills it — `resetToDefaults`, the one call that installs
    /// `DefaultHabits.all` (#228) — rather than through a first-run seeder that
    /// no longer exists.
    private func seededContext() throws -> ModelContext {
        let context = try makeContext()
        try HabitStore(context: context, calendar: calendar, restDay: nil)
            .resetToDefaults(now: today)
        return context
    }

    /// No rest day, stated in the call rather than inherited from whatever the
    /// process happens to hold (#181) — the invented past is asserted day by
    /// day below, and a rest day would put holes in it.
    private func demo(_ context: ModelContext, _ defaults: UserDefaults) -> DemoHistory {
        DemoHistory(
            context: context, defaults: defaults, calendar: calendar, restDay: nil
        )
    }

    @Test("Seeding fills a past for every real habit, and today is never part of it")
    func seedsEveryHabitButNotToday() throws {
        let defaults = makeDefaults()
        let context = try seededContext()
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
        let context = try seededContext()
        let demo = demo(context, defaults)
        try demo.seed(now: today)

        try demo.remove()
        #expect(!demo.isSeeded)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
    }

    @Test("A completion the user logged survives the demo coming out")
    func userDataSurvives() throws {
        let defaults = makeDefaults()
        let context = try seededContext()
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
        let context = try seededContext()
        let demo = demo(context, defaults)

        try demo.seed(now: today)
        let first = try context.fetchCount(FetchDescriptor<Completion>())
        try demo.seed(now: today)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == first)
    }

    @Test("Off and on again rebuilds the same past")
    func reseedIsDeterministic() throws {
        let defaults = makeDefaults()
        let context = try seededContext()
        let demo = demo(context, defaults)

        func snapshot() throws -> [String: [Date: Int]] {
            var result: [String: [Date: Int]] = [:]
            for habit in try context.fetch(FetchDescriptor<Habit>()) where !habit.isSpacer {
                result["\(habit.name) \(habit.frequency)"] = habit.completionCounts(in: calendar)
            }
            return result
        }

        try demo.seed(now: today)
        let first = try snapshot()
        try demo.remove()
        try demo.seed(now: today)
        #expect(try snapshot() == first)
    }

    // The per-day habit's demo used to be asserted here: that a day never
    // held more repetitions than the habit asked for. It is on
    // `feature/daily-habits-2.0` with the branch of `SeededHistory` that drew
    // it (#209).

    @Test("What the demo added is known to the store, not to the defaults")
    func provenanceOutlivesTheDefaults() throws {
        // The crash-in-the-gap case, in the only form it can be observed from:
        // everything outside the store is gone, and the demo is still exactly
        // as identifiable as it was. Under the old record this is the failure —
        // the toggle reads off, and ten weeks of fiction are on the grid for
        // good.
        let defaults = makeDefaults()
        let context = try seededContext()
        let store = HabitStore(context: context, calendar: calendar)
        try demo(context, defaults).seed(now: today)

        let habit = try #require(
            try context.fetch(FetchDescriptor<Habit>()).first { !$0.isSpacer }
        )
        try store.addCompletion(for: habit, on: today)

        let amnesiac = makeDefaults()
        let reopened = demo(context, amnesiac)
        #expect(reopened.isSeeded)

        try reopened.remove()
        #expect(!reopened.isSeeded)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)
        #expect(store.count(for: habit, on: today) == 1)
    }

    @Test("A seeding that was interrupted half-way is still removable")
    func partialSeedIsRemovable() throws {
        // What termination mid-seed leaves: some of the rows, each carrying the
        // mark the rest would have carried. Removal is by that mark, so there
        // is no such thing as a row it wrote and cannot take back.
        let defaults = makeDefaults()
        let context = try seededContext()
        let habit = try #require(
            try context.fetch(FetchDescriptor<Habit>()).first { !$0.isSpacer }
        )

        let session = UUID()
        for offset in 1...3 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            context.insert(Completion(day: day, habit: habit, demoSessionID: session))
        }
        try context.save()

        let demo = demo(context, defaults)
        #expect(demo.isSeeded)
        try demo.remove()
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
    }

    @Test("A demo that failed to save leaves nothing behind, and can be retried")
    func aFailedSeedWritesNothing() throws {
        let url = TestStore.url()
        defer { TestStore.discard(url) }
        let defaults = makeDefaults()

        let setUp = try TestStore.writable(at: url)
        try HabitStore(context: setUp, calendar: calendar, restDay: nil)
            .resetToDefaults(now: today)

        // The same file, opened so that the save cannot land.
        let blocked = try TestStore.readOnly(at: url)
        #expect(throws: (any Error).self) {
            try demo(blocked, defaults).seed(now: today)
        }

        // Reopened: no orphan demo, and the toggle agrees.
        let after = try TestStore.writable(at: url)
        #expect(try after.fetchCount(FetchDescriptor<Completion>()) == 0)
        #expect(!demo(after, defaults).isSeeded)

        try demo(after, defaults).seed(now: today)
        #expect(demo(after, defaults).isSeeded)
        #expect(try after.fetchCount(FetchDescriptor<Completion>()) > 0)
    }

    @Test("A demo recorded before provenance existed is adopted, not stranded")
    func legacyRecordIsAdopted() throws {
        // The upgrade path. An install that switched the demo on under the old
        // record has its ids in the defaults and nothing on the rows, so
        // dropping that key unread would hand exactly these people the bug.
        let defaults = makeDefaults()
        let context = try seededContext()
        let store = HabitStore(context: context, calendar: calendar)
        let habit = try #require(
            try context.fetch(FetchDescriptor<Habit>()).first { !$0.isSpacer }
        )

        var invented: [String] = []
        for offset in 1...4 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let completion = Completion(day: day, habit: habit)
            context.insert(completion)
            invented.append(completion.id.uuidString)
        }
        // One logged by hand, and one id for a completion that no longer
        // exists — a habit deleted since is not an error here.
        try store.addCompletion(for: habit, on: today)
        invented.append(UUID().uuidString)
        try context.save()
        defaults.set(invented, forKey: DemoHistory.legacyIDsKey)

        let demo = demo(context, defaults)
        #expect(demo.isSeeded)
        // Adopted onto the rows, and the old record retired in the same breath.
        #expect(defaults.stringArray(forKey: DemoHistory.legacyIDsKey) == nil)

        try demo.remove()
        #expect(!demo.isSeeded)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)
        #expect(store.count(for: habit, on: today) == 1)
    }

    @Test("The first habit's demo past is perfect, so a full streak is on screen")
    func firstHabitIsPerfect() throws {
        // Position, not identity: SeededHistory.form(at: 0) is .perfect, and
        // the seeder's first habit is daily, so every past day is filled.
        #expect(SeededHistory.form(at: 0) == .perfect)

        let defaults = makeDefaults()
        let context = try seededContext()
        try demo(context, defaults).seed(now: today)

        let first = try #require(
            try context.fetch(
                FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
            ).first { !$0.isSpacer }
        )
        var day = try #require(first.completedDays.min())
        while day < today {
            let isRest = WeekPreferences.isRestDay(day, restDay: nil, calendar: calendar)
            #expect(isRest || first.completedDays.contains(day), "hole at \(day)")
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
        }
    }
}
