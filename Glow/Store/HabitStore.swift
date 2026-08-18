import Foundation
import OSLog
import SwiftData

/// Every write to the store goes through here.
///
/// Reads do not: the grid uses `@Query` so SwiftData drives the updates. This
/// type exists so that "toggle a day" is one operation with one definition of
/// what a day is, rather than the same normalization repeated at each call site.
@MainActor
struct HabitStore {
    private let context: ModelContext
    private let calendar: Calendar
    private static let log = Logger(subsystem: "com.georgklock.glow", category: "store")

    init(context: ModelContext, calendar: Calendar = WeekCalendar.calendar) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - Habits

    @discardableResult
    func addHabit(
        name: String,
        icon: String,
        frequency: Frequency,
        accent: HabitAccent,
        now: Date = Date()
    ) throws -> Habit {
        let habit = Habit(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon,
            frequency: frequency,
            accent: accent,
            createdAt: now,
            sortOrder: try nextSortOrder()
        )
        context.insert(habit)
        try context.save()
        return habit
    }

    func update(
        _ habit: Habit,
        name: String,
        icon: String,
        frequency: Frequency,
        accent: HabitAccent
    ) throws {
        habit.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.icon = icon
        habit.frequency = frequency
        habit.accent = accent
        try context.save()
    }

    func delete(_ habit: Habit) throws {
        // Completions cascade, so this does not leave orphans behind.
        context.delete(habit)
        try context.save()
    }

    /// Rewrites `sortOrder` across the whole list so the stored order matches
    /// what the user just dragged into place.
    func reorder(_ habits: [Habit], from source: IndexSet, to destination: Int) throws {
        var reordered = habits
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in reordered.enumerated() {
            habit.sortOrder = index
        }
        try context.save()
    }

    private func nextSortOrder() throws -> Int {
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let highest = try context.fetch(descriptor).first?.sortOrder
        return (highest ?? -1) + 1
    }

    // MARK: - Completions

    /// Marks the habit done on `date`, or un-marks it if it already is.
    ///
    /// Returns true if the habit ended up completed. Idempotent in the sense
    /// that the stored state only ever has zero or one completion per day: a
    /// duplicate cannot be created by tapping twice quickly, because the second
    /// tap finds the first one and removes it.
    @discardableResult
    func toggleCompletion(for habit: Habit, on date: Date) throws -> Bool {
        let day = WeekCalendar.day(date, calendar: calendar)

        if let existing = (habit.completions ?? []).first(where: { $0.day == day }) {
            habit.completions?.removeAll { $0.id == existing.id }
            context.delete(existing)
            try context.save()
            return false
        }

        let completion = Completion(day: day, habit: habit)
        context.insert(completion)
        habit.completions?.append(completion)
        try context.save()
        return true
    }

    /// Logs a failure without taking down the screen. A habit tracker that
    /// crashes on a write is worse than one that misses a tap, and the log is
    /// where a real store problem would show up.
    static func report(_ error: Error, operation: String) {
        log.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}
