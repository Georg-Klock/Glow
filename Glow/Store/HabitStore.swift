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
    ///
    /// **Blank rows belong to This Week, and only weekly habits take them**
    /// (#143). A blank row is a *layout* row: it holds a position in the week
    /// grid so habits can be clustered around it. Today has no blank-row layout
    /// at all, so a per-day habit filling one would delete a gap somebody
    /// deliberately placed on a screen it never appears on. Per-day habits
    /// append.
    @discardableResult
    func addHabit(
        name: String,
        icon: String,
        frequency: Frequency,
        now: Date = Date()
    ) throws -> Habit {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if !frequency.isCountedPerDay, let blank = try firstBlankRow() {
            // A new habit is a new habit, not the old one wearing new text
            // (#129). Widget configurations and widget intents both resolve by
            // `id`, so a row that keeps its identity through delete-and-refill
            // hands the next habit the last one's widget selection — and any
            // completion a stale widget tap managed to write in between.
            blank.id = UUID()
            blank.name = trimmed
            blank.icon = icon
            blank.frequency = frequency
            blank.createdAt = now
            blank.isSpacer = false
            try clearHistory(of: blank)
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
    /// The habit itself is genuinely gone either way: name, icon, cadence,
    /// every completion — **and its identity** (#129). What survives is the
    /// position, and a position is not an identity.
    ///
    /// **Only a weekly habit leaves a gap** (#143). Blank rows are This Week's
    /// layout, and Today has none; a deleted per-day habit that left one would
    /// insert a blank row into a screen it was never on. Per-day rows are
    /// removed outright.
    func delete(_ habit: Habit) throws {
        guard !habit.isSpacer, !habit.frequency.isCountedPerDay else {
            // A spacer, or a Today habit: nothing here holds a position in the
            // week grid, so there is nothing to keep.
            try clearHistory(of: habit)
            context.delete(habit)
            try context.save()
            return
        }

        try clearHistory(of: habit)
        // A new UUID, and this is the whole of #129. Widget configurations and
        // widget intents resolve habits by `id`: a row that kept its id through
        // delete-and-refill would let a configured widget silently start
        // showing an unrelated habit, and would let a widget tap made against
        // the *deleted* habit — from a snapshot WidgetKit has not replaced yet
        // — land as history on whatever fills the row next. Retiring the id
        // makes both of those resolve to nothing, which is what a deleted
        // habit should be.
        habit.id = UUID()
        habit.name = ""
        habit.icon = ""
        habit.frequency = .daily
        habit.isSpacer = true
        try context.save()
    }

    /// Removes every completion a habit holds.
    ///
    /// Explicitly rather than by cascade: a row being blanked is not a row
    /// being deleted, so nothing would cascade off it, and a reused row that
    /// kept its old days would show them under the new habit's name.
    private func clearHistory(of habit: Habit) throws {
        for completion in habit.completions ?? [] {
            context.delete(completion)
        }
        habit.completions = []
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

    /// What a toggle attempt did.
    ///
    /// A refusal is an outcome rather than an error, because it is the rule
    /// working: the rest day refusing a write is not a failure of anything.
    enum ToggleOutcome: Equatable {
        case completed
        case uncompleted
        /// Nothing was logged and nothing removed. The rest day, a blank row,
        /// or a habit this surface does not own.
        case refused
    }

    /// Whether this row can take a day-shaped write at all.
    ///
    /// Two rejections, and both are about a caller that is out of date rather
    /// than a caller that is wrong (#129). A widget renders in its own process
    /// and its snapshot can outlive the thing it draws, so a tap can arrive for
    /// a habit that has since been deleted — now a blank row — or for one whose
    /// cadence has since changed. The store is the one path both processes
    /// share, so the rule lives here rather than in trust that no button was
    /// offered.
    private func acceptsDayWrite(_ habit: Habit) -> Bool {
        !habit.isSpacer && !habit.frequency.isCountedPerDay
    }

    /// Marks the habit done on `date`, or un-marks it if it already is.
    ///
    /// Idempotent in the sense that the stored state only ever has zero or one
    /// completion per day: a duplicate cannot be created by tapping twice
    /// quickly, because the second tap finds the first one and removes it.
    @discardableResult
    func toggleCompletion(for habit: Habit, on date: Date) throws -> ToggleOutcome {
        let day = WeekCalendar.day(date, calendar: calendar)

        // A rest day is true rest: nothing can be logged on it and nothing
        // un-logged. The grid withholds the tap, but the widget runs in a
        // second process and can hold a surface rendered before the setting
        // changed — so the rule lives here, on the one write path both
        // processes share, rather than in trust that no button was offered.
        // A completion already stored on a rest day stays: records of what
        // happened remain records of what happened.
        guard !WeekPreferences.isRestDay(day, calendar: calendar) else { return .refused }

        // A blank row has no habit to log, and a per-day habit is not
        // day-toggled — its surface is a ring, and one tap there means "one
        // more", not "done". Either write would be a stale caller's, and both
        // used to be accepted. See `acceptsDayWrite` and #129.
        guard acceptsDayWrite(habit) else { return .refused }

        if let existing = (habit.completions ?? []).first(where: { $0.day == day }) {
            habit.completions?.removeAll { $0.id == existing.id }
            context.delete(existing)
            try context.save()
            return .uncompleted
        }

        let completion = Completion(day: day, habit: habit)
        context.insert(completion)
        habit.completions?.append(completion)
        try context.save()
        return .completed
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
        // Nothing is ever logged against a blank row. It has no name to log it
        // under and no surface to show it on, and a completion written here
        // would belong to whatever habit fills the row next (#129).
        guard !habit.isSpacer else { return 0 }
        let day = WeekCalendar.day(date, calendar: calendar)
        let completion = Completion(day: day, habit: habit)
        context.insert(completion)
        habit.completions?.append(completion)
        try context.save()
        return (habit.completions ?? []).count { $0.day == day }
    }

    /// Applies one tap to a per-day habit: one more repetition, or — from a
    /// full ring — a reset to zero. Returns the count the day ends up at.
    ///
    /// The rule itself lives in `DayRing.countAfterTap`; this only translates
    /// its answer into rows. Kept together so the app's ring and the widget's
    /// cannot disagree about what a tap means.
    @discardableResult
    func recordTap(for habit: Habit, on date: Date) throws -> Int {
        guard !habit.isSpacer else { return 0 }
        // A weekly habit has no ring to tap; its surface toggles days instead.
        // Answering with the current count rather than inventing a repetition.
        guard let target = habit.frequency.dailyTarget else {
            return count(for: habit, on: date)
        }

        let next = DayRing.countAfterTap(count: count(for: habit, on: date), target: target)
        if next == 0 {
            try clearDay(for: habit, on: date)
            return 0
        }
        return try addCompletion(for: habit, on: date)
    }

    /// Removes every completion on `date`, and returns how many there were.
    @discardableResult
    func clearDay(for habit: Habit, on date: Date) throws -> Int {
        guard !habit.isSpacer else { return 0 }
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
