import Foundation
import OSLog
import SwiftData

/// Puts the default habits in on first launch.
@MainActor
struct HabitSeeder {
    /// Set once the seed has been attempted, whether or not it inserted
    /// anything.
    ///
    /// The flag is what stops a user who deletes every habit from finding them
    /// all back the next morning. "Is the store empty" is not the same question
    /// as "has this install ever been seeded", and using the first to answer the
    /// second is how a tracker becomes impossible to empty.
    static let seededKey = "didSeedDefaultHabits"

    private let store: HabitStore
    private let context: ModelContext
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "com.georgklock.glow", category: "seed")

    init(context: ModelContext, defaults: UserDefaults = .standard, calendar: Calendar = WeekCalendar.calendar) {
        self.context = context
        self.defaults = defaults
        self.store = HabitStore(context: context, calendar: calendar)
    }

    /// Inserts the defaults if this install has never been seeded and the store
    /// is empty. Returns how many were added.
    @discardableResult
    func seedIfNeeded(now: Date = Date()) throws -> Int {
        guard !defaults.bool(forKey: Self.seededKey) else { return 0 }

        // Belt and braces: an install that already has habits arrived here some
        // other way, and adding six more to someone's real list would be rude.
        let existing = try context.fetchCount(FetchDescriptor<Habit>())
        defaults.set(true, forKey: Self.seededKey)
        guard existing == 0 else { return 0 }

        let today = WeekCalendar.day(now)
        for template in DefaultHabits.all {
            guard !template.isSpacer else {
                try store.addSpacer(now: now)
                continue
            }
            let habit = try store.addHabit(
                name: template.name,
                icon: template.icon,
                frequency: template.frequency,
                now: now
            )
            // Invented, deterministic, and never touching today. See
            // SeededHistory for what that costs and how to switch it off.
            for day in SeededHistory.completions(
                for: template.frequency,
                form: template.form,
                seed: template.seed,
                today: today
            ) {
                // Added, not toggled. The seed for a per-day habit names the
                // same day once per repetition, and a toggle would take the
                // second one back off again.
                _ = try store.addCompletion(for: habit, on: day)
            }
        }

        Self.log.info("Seeded \(DefaultHabits.all.count) default habits")
        return DefaultHabits.all.count
    }
}
