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

    /// How many completions fall on each civil day that has any.
    ///
    /// **The one place rows become history**, and the only one that reads
    /// `Completion` at all. Everything below is a projection of this small
    /// dictionary, which is deliberate on two counts: the identity stays
    /// zone-free right up to the moment something has to draw it, and the
    /// expensive half — a fetch and a reduce over every row a habit has — is one
    /// value that depends on nothing but the store. That is the seam a cache
    /// belongs behind (#135); a projection keyed by a calendar is not, because
    /// the calendar can change under it.
    ///
    /// A weekly-cadence habit only ever reaches one per day. A per-day habit is
    /// the reason this is a count and not a set — and the reason a repetition is
    /// stored as its own row rather than as a number on a single row. Rows merge
    /// when two devices sync; a counter is last-writer-wins, so two glasses of
    /// water logged on two devices would come back as one.
    var completionDayCounts: [DayID: Int] {
        liveCompletions.reduce(into: [:]) { counts, completion in
            counts[completion.dayID, default: 0] += 1
        }
    }

    /// The same counts, over a bounded stretch of days.
    ///
    /// One habit's half of `Habit.dayCounts(of:within:in:)`, for the surfaces
    /// that hold a habit rather than a list of them — a widget tap deciding
    /// whether it met a weekly goal, which is a question about one week (#135).
    /// A habit with no context filters the rows it carries, so a fixture
    /// answers the same as a stored row.
    func completionDayCounts(within days: ClosedRange<DayID>) -> [DayID: Int] {
        guard let modelContext else {
            return completionDayCounts.filter { days.contains($0.key) }
        }
        return Habit.dayCounts(of: [self], within: days, in: modelContext)[id] ?? [:]
    }

    /// The same counts, placed on the timeline `calendar` describes.
    ///
    /// Everything week-shaped compares days by equality against the midnights
    /// `WeekCalendar.week` produces, so the projection has to use the same
    /// calendar those came from. In the app that is `WeekCalendar.calendar` on
    /// both sides; a test that pins a calendar has to pin it here too, and
    /// saying so is the point of the parameter.
    func completionCounts(in calendar: Calendar) -> [Date: Int] {
        completionDayCounts.reduce(into: [:]) { counts, entry in
            counts[entry.key.date(in: calendar)] = entry.value
        }
    }

    var completionCounts: [Date: Int] { completionCounts(in: WeekCalendar.calendar) }

    /// Every day with at least one completion.
    func completedDays(in calendar: Calendar) -> Set<Date> {
        Set(completionDayCounts.keys.map { $0.date(in: calendar) })
    }

    var completedDays: Set<Date> { completedDays(in: WeekCalendar.calendar) }

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

    func snapshot(calendar: Calendar = WeekCalendar.calendar) -> HabitSnapshot {
        snapshot(dayCounts: completionDayCounts, calendar: calendar)
    }

    /// A snapshot holding only the days `days` covers, and nothing before or
    /// after them. See `Habit.snapshots(of:within:calendar:)` for what may be
    /// handed one.
    func snapshot(
        within days: ClosedRange<DayID>, calendar: Calendar = WeekCalendar.calendar
    ) -> HabitSnapshot {
        snapshot(dayCounts: completionDayCounts(within: days), calendar: calendar)
    }

    /// A snapshot from counts somebody else already took.
    ///
    /// The projection, separated from the read that feeds it (#135), so a
    /// caller that has already read a bounded stretch of history does not read
    /// it again per habit. The calendar stays on this side, where it belongs:
    /// the counts are zone-free and only the projection is not.
    func snapshot(dayCounts: [DayID: Int], calendar: Calendar) -> HabitSnapshot {
        HabitSnapshot(
            id: id,
            name: name,
            icon: icon,
            frequency: frequency,
            completionCounts: dayCounts.reduce(into: [:]) { counts, entry in
                counts[entry.key.date(in: calendar)] = entry.value
            },
            isSpacer: isSpacer
        )
    }

    /// How many completions each of these habits has on each civil day of
    /// `days`, in one pass over the store.
    ///
    /// **The saving is the range, not the single fetch**, and that is a
    /// measurement rather than a guess. Twelve habits with two years each —
    /// 8,760 completions, alternated arms in one process, medians of eight
    /// rounds, over three runs: one fetch per habit over the whole history
    /// 188–194ms, one shared fetch over the whole history 183–205ms, one
    /// shared fetch bounded to a week 2.4–2.5ms. The first two are the same
    /// number. Grouping *n* habits' rows into one query saves *n − 1* round
    /// trips and spends them again faulting the habit each row points at, and
    /// it still materializes every row there has ever been. Reading seven days
    /// materializes seven days. See `Tests/HistoryProjectionTests.swift`.
    ///
    /// So a caller that draws a bounded stretch of time should pass it. A
    /// caller that genuinely needs the whole history — the export — should not
    /// bother, and `snapshots(of:within:calendar:)` says so by mapping
    /// `snapshot()` when there is no range.
    ///
    /// Habits outside `habits` are dropped rather than returned, so a caller
    /// that fetched the weekly cadences does not also get the per-day ones.
    ///
    /// **This is not a cache and nothing here is remembered** — see
    /// `snapshots(of:within:calendar:)` for why not.
    static func dayCounts(
        of habits: [Habit], within days: ClosedRange<DayID>? = nil, in context: ModelContext
    ) -> [UUID: [DayID: Int]] {
        let wanted = Set(habits.map(\.id))
        guard !wanted.isEmpty else { return [:] }
        var descriptor = FetchDescriptor<Completion>(predicate: rowsFalling(in: days))
        // Fault the habit each row points at in the same pass. Without this
        // the group below asks for it row by row, which trades n fetches of
        // completions for rather more fetches of habits.
        descriptor.relationshipKeyPathsForPrefetching = [\.habit]
        guard let rows = try? context.fetch(descriptor) else { return [:] }

        var counts: [UUID: [DayID: Int]] = [:]
        for row in rows {
            guard let habitID = row.habit?.id, wanted.contains(habitID) else { continue }
            let dayID = row.dayID
            if let days, !days.contains(dayID) { continue }
            counts[habitID, default: [:]][dayID, default: 0] += 1
        }
        return counts
    }

    /// The rows that could fall inside `days`, as something SQLite can answer.
    ///
    /// **A legacy row is always fetched, whatever the range** (#130, #135). Its
    /// `dayKey` is empty and its day is *inferred* from the untouched instant,
    /// so a predicate on the key alone would silently skip exactly the rows the
    /// day-identity work is about — and it would skip them differently
    /// depending on how far through the backfill a store happened to be. Empty
    /// keys come back and `dayID` settles them in memory, which is why this
    /// needs no way to ask whether a store is fully stamped: on a stamped store
    /// the empty-key branch matches nothing and the range is doing all the
    /// work, on an unstamped one it degrades to the scan that already happens
    /// today, and both answer the same.
    ///
    /// The comparison is on the text because the text is what sorts like the
    /// dates do — that is the whole reason `DayID.text` is zero-padded.
    private static func rowsFalling(in days: ClosedRange<DayID>?) -> Predicate<Completion>? {
        guard let days else { return nil }
        let low = days.lowerBound.text
        let high = days.upperBound.text
        return #Predicate<Completion> {
            $0.dayKey == "" || ($0.dayKey >= low && $0.dayKey <= high)
        }
    }

    /// Snapshots of a whole list, reading only the days `within` covers.
    ///
    /// What every list-shaped surface that draws a bounded stretch of time
    /// should call instead of mapping `snapshot()`: the week grid draws seven
    /// days, the year draws one year, the month widget draws one month, and
    /// each of them was reading every completion of every habit, once per
    /// habit, on every redraw.
    ///
    /// **A snapshot made this way holds only those days**, which is the one
    /// thing to know before passing one somewhere else. Everything week-shaped
    /// — `WeekGrid`, `WeekSpans`, `WeekDots`, `GoalMet`, `RestCut` — asks only
    /// about days inside the week it is given, so a week's worth is all a week
    /// needs; `HistoryExport` and the CSV are the callers that genuinely mean
    /// *all of it*, and they pass no range.
    ///
    /// **Per render, not across renders, and that is deliberate** (#135, #145).
    /// The tempting version of this is a cache on the habit, taken once and
    /// invalidated when the app writes. It cannot be made honest here: the
    /// widget's intents open their own container against the same App Group
    /// file, the app is never told when they write, and a cache the other
    /// process cannot invalidate is a wrong number that survives until
    /// something unrelated redraws. So the pass is shared within one render and
    /// dropped at the end of it, which is a cost the *number of habits* no
    /// longer multiplies.
    ///
    /// Maps `snapshot()` in two cases: when there is no range, where the shared
    /// pass measured no better than a fetch per habit and so is not worth the
    /// second code path, and when no habit here has a context — fixtures, which
    /// carry their rows in the cached array and have nothing to fetch from.
    static func snapshots(
        of habits: [Habit],
        within days: ClosedRange<DayID>? = nil,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [HabitSnapshot] {
        guard let days, let context = habits.lazy.compactMap(\.modelContext).first else {
            return habits.map { $0.snapshot(calendar: calendar) }
        }
        let counts = dayCounts(of: habits, within: days, in: context)
        return habits.map { habit in
            habit.snapshot(dayCounts: counts[habit.id] ?? [:], calendar: calendar)
        }
    }
}
