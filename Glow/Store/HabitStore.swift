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

    /// Adds a habit, filling the first blank row if there is one.
    ///
    /// A blank row is a position waiting to be used, so a new habit takes it
    /// rather than landing past it — the row count stays put and whatever
    /// clustering the rows were expressing survives. Appending is what happens
    /// when there are none left.
    ///
    /// The mirror of `delete`, which leaves a blank row behind rather than
    /// collapsing one. Between them a row's existence is stable and only its
    /// contents change, which is what makes the grid something you can arrange.
    @discardableResult
    func addHabit(
        name: String,
        icon: String,
        frequency: Frequency,
        now: Date = Date()
    ) throws -> Habit {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let blank = try firstBlankRow() {
            blank.name = trimmed
            blank.icon = icon
            blank.frequency = frequency
            blank.createdAt = now
            blank.isSpacer = false
            try context.save()
            return blank
        }

        let habit = Habit(
            name: trimmed,
            icon: icon,
            frequency: frequency,
            createdAt: now,
            sortOrder: try nextSortOrder()
        )
        context.insert(habit)
        try context.save()
        return habit
    }

    /// The topmost blank row, or nil when the grid has none.
    private func firstBlankRow() throws -> Habit? {
        var descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isSpacer },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// A blank row, held in the order so habits can be grouped around it.
    @discardableResult
    func addSpacer(now: Date = Date()) throws -> Habit {
        let spacer = Habit(
            name: "",
            icon: "",
            frequency: .daily,
            createdAt: now,
            sortOrder: try nextSortOrder(),
            isSpacer: true
        )
        context.insert(spacer)
        try context.save()
        return spacer
    }

    func update(
        _ habit: Habit,
        name: String,
        icon: String,
        frequency: Frequency
    ) throws {
        habit.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.icon = icon
        habit.frequency = frequency
        try context.save()
    }

    /// Deleting a habit leaves a blank row where it was. Deleting a blank row
    /// removes it.
    ///
    /// The grid is a layout the user arranges, and collapsing a row pulls
    /// everything below it up a line — so removing one habit silently rewrites
    /// the grouping of every habit under it. Leaving a gap keeps what they
    /// arranged, and the gap is a real thing they can then delete or drag.
    ///
    /// The habit itself is genuinely gone either way: name, icon, cadence and
    /// every completion. What survives is the position.
    func delete(_ habit: Habit) throws {
        guard !habit.isSpacer else {
            context.delete(habit)
            try context.save()
            return
        }

        // Completions are removed explicitly rather than left to cascade: the
        // row is not being deleted, so nothing would cascade off it.
        for completion in habit.completions ?? [] {
            context.delete(completion)
        }
        habit.completions = []
        habit.name = ""
        habit.icon = ""
        habit.frequency = .daily
        habit.isSpacer = true
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

    // MARK: - Counts
    //
    // A per-day habit is logged several times on one day, so these are the
    // storage primitives `toggleCompletion` cannot express. The *rule* about
    // what a tap does — one more, and a full ring resets to zero — deliberately
    // lives elsewhere (#18); all this knows is how to add one and how to clear
    // a day.

    /// How many times the habit is logged on `date`.
    func count(for habit: Habit, on date: Date) -> Int {
        let day = WeekCalendar.day(date, calendar: calendar)
        return (habit.completions ?? []).count { $0.day == day }
    }

    /// Records one more completion on `date`, and returns the new count.
    ///
    /// A repetition is its own row rather than a number on a shared one, so two
    /// devices logging the same habit merge into two completions instead of
    /// overwriting each other's counter.
    @discardableResult
    func addCompletion(for habit: Habit, on date: Date) throws -> Int {
        let day = WeekCalendar.day(date, calendar: calendar)
        let completion = Completion(day: day, habit: habit)
        context.insert(completion)
        habit.completions?.append(completion)
        try context.save()
        return (habit.completions ?? []).count { $0.day == day }
    }

    /// Removes every completion on `date`, and returns how many there were.
    @discardableResult
    func clearDay(for habit: Habit, on date: Date) throws -> Int {
        let day = WeekCalendar.day(date, calendar: calendar)
        let doomed = (habit.completions ?? []).filter { $0.day == day }
        guard !doomed.isEmpty else { return 0 }

        let ids = Set(doomed.map(\.id))
        habit.completions?.removeAll { ids.contains($0.id) }
        for completion in doomed {
            context.delete(completion)
        }
        try context.save()
        return doomed.count
    }

    /// Logs a failure without taking down the screen. A habit tracker that
    /// crashes on a write is worse than one that misses a tap, and the log is
    /// where a real store problem would show up.
    static func report(_ error: Error, operation: String) {
        log.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}
