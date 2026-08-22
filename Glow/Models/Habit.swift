import Foundation
import SwiftData

/// A tracked habit.
///
/// Stored shape notes, both aimed at a later CloudKit sync being a change of
/// configuration rather than a migration: every property has a default value,
/// there are no unique constraints, and the relationship is optional. CloudKit
/// requires all three, and retrofitting them means rewriting the store.
///
/// `Frequency` is stored as its two parts rather than as an encoded enum so the
/// column is queryable and readable in the store, and so a future schema change
/// does not hinge on an enum's Codable representation.
@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = HabitSymbol.default
    var isDaily: Bool = true
    /// Only meaningful when `isDaily` is false.
    var timesPerWeek: Int = 3
    /// How many times a day, or **zero for a habit counted across a week**.
    ///
    /// A sentinel rather than a third discriminator column beside `isDaily`,
    /// because two columns that both claim to say which kind a habit is can
    /// disagree, and then something has to decide which one wins. Zero is safe
    /// by construction: `Frequency(timesPerDay:)` clamps into 1...12, so no real
    /// per-day habit can store it, and every row written before this existed
    /// reads back as exactly what it was.
    var timesPerDay: Int = 0
    /// Retained so the stored schema does not change. The app committed to a
    /// single colour, so nothing reads this; dropping the column would be a
    /// migration for no gain.
    var accentRaw: String = ""
    var createdAt: Date = Date.distantPast
    var sortOrder: Int = 0

    /// A blank row: no name, no icon, no track, nothing to complete.
    ///
    /// A row rather than a setting, because what it is for is *position* — it
    /// holds a gap in the order so habits can be clustered into morning, midday
    /// and evening without inventing sections, headers or a second axis of
    /// grouping to keep in step with the first.
    ///
    /// Stored on `Habit` rather than as its own model so it inherits sortOrder,
    /// reordering and deletion for free — a second sorted list merged against
    /// this one is more machinery than a flag. The cost is that every query
    /// that means "real habits" has to say so; `HabitStore.habits` and the
    /// snapshot's `isSpacer` are how that stays honest.
    var isSpacer: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Completion.habit)
    var completions: [Completion]? = []

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        frequency: Frequency,
        createdAt: Date,
        sortOrder: Int,
        isSpacer: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isSpacer = isSpacer
        self.completions = []
        self.frequency = frequency
    }

    var frequency: Frequency {
        get {
            if timesPerDay > 0 { return .timesPerDay(timesPerDay) }
            return isDaily ? .daily : Frequency(timesPerWeek: timesPerWeek)
        }
        set {
            switch newValue {
            case .daily:
                timesPerDay = 0
                isDaily = true
            case .timesPerWeek(let count):
                timesPerDay = 0
                isDaily = false
                timesPerWeek = count
            case .timesPerDay(let count):
                // The weekly columns are left as they were on purpose: a habit
                // switched to per-day and back should come out of it with the
                // cadence it went in with.
                timesPerDay = count
            }
        }
    }

    /// Counted within a day rather than across a week.
    var isCountedPerDay: Bool { timesPerDay > 0 }

    /// What the week-shaped surfaces fetch: the weekly cadences, plus the blank
    /// rows that hold their positions. One definition rather than the same
    /// clause written into the grid, the year view and the widget separately,
    /// where the three could drift and only two would be noticed.
    static let countedPerWeek = #Predicate<Habit> { $0.timesPerDay == 0 }

    /// What Today fetches: the several-times-a-day habits, and nothing else.
    /// The complement of `countedPerWeek` — a spacer holds a position in the
    /// week grid, so it belongs to that side and never appears here.
    static let countedPerDay = #Predicate<Habit> { $0.timesPerDay > 0 }

    /// How many completions fall on each day that has any.
    ///
    /// A weekly-cadence habit only ever reaches one per day. A per-day habit is
    /// the reason this is a count and not a set — and the reason a repetition is
    /// stored as its own row rather than as a number on a single row. Rows merge
    /// when two devices sync; a counter is last-writer-wins, so two glasses of
    /// water logged on two devices would come back as one.
    var completionCounts: [Date: Int] {
        liveCompletions.reduce(into: [:]) { counts, completion in
            counts[completion.day, default: 0] += 1
        }
    }

    /// Every day with at least one completion.
    var completedDays: Set<Date> {
        Set(liveCompletions.map(\.day))
    }

    /// This habit's completions, fetched rather than remembered.
    ///
    /// **`completions` is a cached array and it can outlive its rows** (#145).
    /// SwiftData fetches a to-many relationship once and holds it on the model
    /// object; reading `.day` on an element whose row has since been deleted
    /// trips `_InvalidFutureBackingData`, which is a `precondition` inside
    /// SwiftData rather than a Swift error — nothing here could catch it even
    /// if something were placed to try.
    ///
    /// The rows go out from under it because **two processes write this store**.
    /// `ToggleHabitIntent` and `TapHabitIntent` open their own `ModelContainer`
    /// against the same App Group file, and nothing tells the app's context to
    /// re-fetch when the widget's deletes a completion. The app tells the widget
    /// about every write it makes; the reverse path does not exist.
    ///
    /// So this reads through the context instead. A fetch cannot hand back a
    /// row that is already gone, which sidesteps cross-process invalidation
    /// rather than requiring it — that is the more complete fix and it is a
    /// separate question, because whether SwiftData exposes persistent-history
    /// notifications the way Core Data does is not established here.
    ///
    /// Falls back to the cached array only when there is no context to ask,
    /// which is a model object that was built but never inserted — a fixture,
    /// in practice, where the array is the only truth there is.
    private var liveCompletions: [Completion] {
        guard let modelContext else { return completions ?? [] }
        let habitID = id
        let descriptor = FetchDescriptor<Completion>(
            predicate: #Predicate { $0.habit?.id == habitID }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func snapshot() -> HabitSnapshot {
        HabitSnapshot(
            id: id,
            name: name,
            icon: icon,
            frequency: frequency,
            completionCounts: completionCounts,
            isSpacer: isSpacer
        )
    }
}
