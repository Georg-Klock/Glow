import Foundation
import SwiftData
import Testing
@testable import Glow

/// #209: the per-day habits an earlier build seeded come out of a real store.
///
/// The code that read `timesPerDay` is gone; the rows are not. #123 shipped
/// five per-day defaults, so every install seeded by a build that carried them
/// holds habits nothing in this build can draw, edit or delete.
///
/// **The rows are written the way that build wrote them**, which is by setting
/// the column directly: `Habit.frequency`'s setter can no longer produce one,
/// and a fixture that went through the setter would be testing that the
/// migration finds nothing. This is the one place the removed kind's stored
/// shape is still constructed, and it has to be, or the migration is asserted
/// against a store it will never meet.
@Suite("Daily habit migration")
@MainActor
struct DailyHabitMigrationTests {
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
        let suite = "daily-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A habit as a build that shipped the per-day kind stored one: the column
    /// set, with `count` repetitions logged on `today`.
    @discardableResult
    private func perDayRow(
        _ context: ModelContext, name: String = "Hydration", count: Int = 3
    ) -> Habit {
        let habit = Habit(
            name: name, icon: "drop", frequency: .timesPerWeek(3),
            createdAt: today, sortOrder: 99
        )
        habit.timesPerDay = 8
        context.insert(habit)
        for _ in 0..<count {
            let completion = Completion(day: today, habit: habit, calendar: calendar)
            context.insert(completion)
            habit.completions?.append(completion)
        }
        return habit
    }

    @Test("A per-day habit and its history come out; a weekly one does not")
    func staleRowsAreRemoved() throws {
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        let kept = try store.addHabit(name: "Read", icon: "book", frequency: .timesPerWeek(3))
        try store.toggleCompletion(for: kept, on: today)
        perDayRow(context)
        try context.save()

        #expect(try DailyHabitMigration.runIfNeeded(
            context: context, defaults: makeDefaults()
        ) == 1)

        let rows = try context.fetch(FetchDescriptor<Habit>())
        #expect(rows.map(\.name) == ["Read"])
        // The completions go with it, and only its own do. A cascade would
        // reach these too; deleting them outright is what makes that a promise
        // rather than a hope — see `resetToDefaults`.
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)
    }

    @Test("A blank row is not a per-day row and survives")
    func spacersSurvive() throws {
        // `timesPerDay == 0` is what a blank row has always stored, so the
        // predicate that finds the residue must not find the grid's own layout.
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        try store.addSpacer()
        perDayRow(context)
        try context.save()

        try DailyHabitMigration.runIfNeeded(context: context, defaults: makeDefaults())

        let rows = try context.fetch(FetchDescriptor<Habit>())
        #expect(rows.count == 1)
        #expect(rows.first?.isSpacer == true)
    }

    @Test("It runs once, and a store with nothing to do still records that")
    func runsOnce() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        #expect(try DailyHabitMigration.runIfNeeded(context: context, defaults: defaults) == 0)
        #expect(defaults.bool(forKey: DailyHabitMigration.migratedKey))

        // A row appearing afterwards is not swept: nothing in this build can
        // create one, so a second sweep would only be able to find something
        // somebody put there deliberately.
        perDayRow(context)
        try context.save()
        #expect(try DailyHabitMigration.runIfNeeded(context: context, defaults: defaults) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == 1)
    }

    @Test("Until it runs, the residue is invisible to every surface")
    func residueIsFilteredOut() throws {
        // The reason `Habit.weekly` survives as a predicate rather than being
        // deleted for being true of everything: the widget's process never runs
        // the migration, so between an update and the next launch of the app a
        // home screen can redraw against a store that still holds these rows.
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        try store.addHabit(name: "Read", icon: "book", frequency: .timesPerWeek(3))
        let stale = perDayRow(context)
        try context.save()

        let shown = try context.fetch(FetchDescriptor<Habit>(predicate: Habit.weekly))
        #expect(shown.map(\.name) == ["Read"])

        // And nothing can be logged against it either, on the one write path
        // both processes share.
        #expect(try store.toggleCompletion(for: stale, on: today) == .refused)
    }
}
