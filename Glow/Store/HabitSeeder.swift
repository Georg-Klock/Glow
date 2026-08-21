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

    /// Whether the invented past is seeded alongside the habits.
    ///
    /// Debug builds keep it: an empty grid shows none of what the app is for,
    /// and the design has to be judged with something in it. A real install
    /// opens with the habits and an empty grid, because a tracker that opens
    /// showing a streak you did not earn is lying on the first screen. Today
    /// is never pre-filled in either mode.
    #if DEBUG
    static let seedsHistoryByDefault = true
    #else
    static let seedsHistoryByDefault = false
    #endif

    private let seedsHistory: Bool

    init(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        calendar: Calendar = WeekCalendar.calendar,
        seedsHistory: Bool = HabitSeeder.seedsHistoryByDefault
    ) {
        self.context = context
        self.defaults = defaults
        self.store = HabitStore(context: context, calendar: calendar)
        self.seedsHistory = seedsHistory
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
            // Invented, deterministic, and never touching today. Debug builds
            // only — see `seedsHistoryByDefault` and SeededHistory.
            guard seedsHistory else { continue }
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
