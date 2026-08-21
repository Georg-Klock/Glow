import Foundation
import SwiftData

/// Ten weeks of invented past, switched on and off in Settings.
///
/// The demo exists because an empty grid shows none of what the app is for —
/// no run of light, no shape to a week — and judging the design against a
/// blank slate is judging a different app. It is also a lie, which is why it
/// is a toggle rather than a default: nothing invented appears unless asked
/// for, and switching it off removes **exactly what it added**, never a
/// completion the user logged themselves.
///
/// That exactness is the design constraint here. The seeded completions are
/// remembered by id in the App Group defaults, so removal deletes by id
/// rather than recomputing which days "look seeded" — a recomputation would
/// have to guess whether a completion on a matching day was invented or
/// earned, and a demo that can delete real data is worse than no demo.
///
/// The toggle's state is derived from that record rather than stored beside
/// it: "is the demo in" and "what did the demo add" cannot disagree.
@MainActor
struct DemoHistory {
    static let idsKey = "demoHistoryCompletionIDs"

    private let context: ModelContext
    private let calendar: Calendar
    private let defaults: UserDefaults

    init(
        context: ModelContext,
        defaults: UserDefaults = GlowSettings.store,
        calendar: Calendar = WeekCalendar.calendar
    ) {
        self.context = context
        self.defaults = defaults
        self.calendar = calendar
    }

    var isSeeded: Bool { !storedIDs.isEmpty }

    private var storedIDs: [String] {
        defaults.stringArray(forKey: Self.idsKey) ?? []
    }

    /// Invents a past for every real habit. A no-op while one is already in,
    /// so the toggle cannot stack two demos on top of each other.
    ///
    /// The first habit is perfect — a full streak is the thing the demo most
    /// needs on screen — and the rest cycle down to patchy so a missed day is
    /// on screen too. Each habit's days are derived from its own id, so
    /// switching the demo off and on rebuilds the same past. Today is never
    /// touched: the open slot is the one thing the app is for.
    func seed(now: Date = Date()) throws {
        guard !isSeeded else { return }

        let today = WeekCalendar.day(now, calendar: calendar)
        let habits = try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        )

        var ids: [String] = []
        var position = 0
        for habit in habits where !habit.isSpacer {
            let days = SeededHistory.completions(
                for: habit.frequency,
                form: SeededHistory.form(at: position),
                seed: SeededHistory.seed(for: habit.id),
                today: today,
                calendar: calendar
            )
            position += 1

            for day in days {
                let completion = Completion(day: day, habit: habit)
                context.insert(completion)
                habit.completions?.append(completion)
                ids.append(completion.id.uuidString)
            }
        }

        try context.save()
        defaults.set(ids, forKey: Self.idsKey)
    }

    /// Removes exactly the completions `seed` recorded. Anything logged by
    /// hand — before, during or after the demo — survives, including taps on
    /// days the demo also filled. Ids that no longer resolve are skipped:
    /// deleting a habit cascades its completions away, and that is not an
    /// error here.
    func remove() throws {
        let ids = Set(storedIDs.compactMap(UUID.init))
        guard !ids.isEmpty else { return }

        for completion in try context.fetch(FetchDescriptor<Completion>())
        where ids.contains(completion.id) {
            completion.habit?.completions?.removeAll { $0.id == completion.id }
            context.delete(completion)
        }

        try context.save()
        defaults.removeObject(forKey: Self.idsKey)
    }
}
