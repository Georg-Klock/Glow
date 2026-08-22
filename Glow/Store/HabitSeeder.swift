import Foundation
import OSLog
import SwiftData

/// Puts the default habits in on first launch.
///
/// Habits only, in every configuration. The invented past that briefly rode
/// along here is `DemoHistory` now — a Settings toggle, asked for rather than
/// assumed — so every fresh install opens with the habits and an empty grid.
@MainActor
struct HabitSeeder {
    /// Set once the store holds the defaults, or holds habits that make seeding
    /// unnecessary.
    ///
    /// The flag is what stops a user who deletes every habit from finding them
    /// all back the next morning. "Is the store empty" is not the same question
    /// as "has this install ever been seeded", and using the first to answer the
    /// second is how a tracker becomes impossible to empty.
    ///
    /// **It is written last** (#140). It used to go in before the inserts, so
    /// an interruption anywhere in them left a partial list that nothing would
    /// ever repair: the flag said seeded, the store held four habits of eleven,
    /// and the two never spoke again. Written after the save, the failure case
    /// is a store that is exactly as it was and a next launch that tries again.
    ///
    /// The flag is a Bool and has no version in it, on purpose. The question it
    /// answers is "has this install ever been seeded", and that question does
    /// not get a new answer when the seed set changes — a version that bumped
    /// would push a new list onto people who had already arranged the old one,
    /// which is the same failure as re-seeding an emptied store. A changed seed
    /// set is for installs that have not been seeded yet.
    static let seededKey = "didSeedDefaultHabits"

    private let store: HabitStore
    private let context: ModelContext
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "com.georgklock.glow", category: "seed")

    init(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        calendar: Calendar = WeekCalendar.calendar
    ) {
        self.context = context
        self.defaults = defaults
        self.store = HabitStore(context: context, calendar: calendar)
    }

    /// Inserts the defaults if this install has never been seeded and the store
    /// is empty. Returns how many were added.
    ///
    /// **Retriable.** Nothing here is remembered until it is true: the insert
    /// is one transaction, and the flag that stops it happening again goes in
    /// after that transaction has landed. A failure at any point leaves an
    /// unseeded install with an empty store, and the next launch does the whole
    /// thing again.
    ///
    /// The one order that cannot be made atomic is the save and the flag, which
    /// are two different stores. It converges rather than being guarded: if the
    /// save lands and the flag does not, the next launch finds habits it did not
    /// record putting there, and records that instead of adding eleven more.
    /// Whichever way that gap is crossed, the install ends up seeded exactly
    /// once.
    @discardableResult
    func seedIfNeeded(now: Date = Date()) throws -> Int {
        guard !defaults.bool(forKey: Self.seededKey) else { return 0 }

        // Belt and braces: an install that already has habits arrived here some
        // other way — a restore, or a seeding whose flag never made it — and
        // adding eleven more rows to someone's real list would be rude.
        guard try context.fetchCount(FetchDescriptor<Habit>()) == 0 else {
            defaults.set(true, forKey: Self.seededKey)
            return 0
        }

        let added = try store.addAll(DefaultHabits.all, now: now)
        defaults.set(true, forKey: Self.seededKey)

        Self.log.info("Seeded \(added) default habits")
        return added
    }
}
