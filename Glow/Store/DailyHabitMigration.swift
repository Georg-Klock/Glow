import Foundation
import OSLog
import SwiftData

/// Takes the per-day habits out of a store that already has them (#209).
///
/// Removing the code that reads `timesPerDay` does not remove the rows. #123's
/// seed set shipped five per-day habits — Sunlight, Protein Meal, Move, Breathe,
/// Hydration — so every install seeded by a build that carried the feature holds
/// them, and there is no screen left that draws them. A row nothing can show and
/// nothing can edit is worse than a deleted one: it is invisible, it is still
/// counted by anything that counts habits, and it comes back the moment a future
/// build queries without the filter.
///
/// **This destroys history, and the loss is real.** A habit's completions
/// cascade with it, so anybody who logged glasses of water during the window the
/// feature shipped in loses those days. That is stated plainly in the release
/// notes for the build carrying this rather than discovered afterwards, and it
/// is the price of pulling the feature rather than shipping it half-drawn. The
/// feature itself is preserved whole on `feature/daily-habits-2.0`.
///
/// **Once per install**, on its own flag: a store with nothing left to migrate
/// still runs the fetch once and then never again, and — more to the point — a
/// person who later creates nothing of the kind cannot have this run against
/// them a second time, because there is no way left to make a row it would
/// match.
///
/// **Run from `GlowApp.init`, on every launch that opens a store** (#239). It
/// hung off `WeeklyGridView` appearing until then, on the reasoning that the
/// store is opened for that screen — but the widget configurator is a separate
/// process reading the same file with no screen involved at all, and it was
/// offering rows this had never been asked to delete. A sweep that runs unasked
/// cannot be scheduled by a view; the only thing every store-opening launch has
/// in common is the launch.
///
/// The flag is written **after** the save, the shape first-run seeding's flag
/// established in #140: a failure anywhere leaves the store exactly as it was
/// and the next launch tries again. This is the last flag of that shape in the
/// app — seeding's went with the seeder in #228, because a sweep runs unasked
/// and needs to remember, while a tap does not.
@MainActor
enum DailyHabitMigration {
    /// Set once this install has been swept.
    static let migratedKey = "didMigrateDailyHabitsOut"

    private static let log = Logger(subsystem: "com.georgklock.glow", category: "seed")

    /// Deletes every habit still counted per day. Returns how many there were.
    ///
    /// Completions are deleted explicitly rather than left to the `.cascade`
    /// rule, for the reason `HabitStore.resetToDefaults` does it: the cascade
    /// reaches every completion attached to a habit, and a completion whose
    /// habit reference is nil would survive one. The promise here is that
    /// nothing of these habits is left.
    @discardableResult
    static func runIfNeeded(
        context: ModelContext, defaults: UserDefaults = .standard
    ) throws -> Int {
        guard !defaults.bool(forKey: migratedKey) else { return 0 }

        let stale = try context.fetch(
            FetchDescriptor<Habit>(predicate: #Predicate { $0.timesPerDay > 0 })
        )
        for habit in stale {
            for completion in habit.completions ?? [] {
                context.delete(completion)
            }
            habit.completions = []
            context.delete(habit)
        }
        if !stale.isEmpty {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            WidgetRefresh.invalidate()
            log.info("Removed \(stale.count) per-day habits and their history")
        }

        defaults.set(true, forKey: migratedKey)
        return stale.count
    }
}
