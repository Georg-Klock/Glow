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
    /// **Always zero in a shipped build, and kept anyway** (#209).
    ///
    /// This is what a per-day habit stored: how many repetitions a day it asked
    /// for, with zero meaning "counted across a week instead". The per-day kind
    /// is out of the app — see `Frequency` — so nothing writes anything but zero
    /// here any more.
    ///
    /// The column stays for two reasons. Dropping it is a schema change, and the
    /// stored shape is deliberately sync-ready rather than minimal. And it is
    /// what `DailyHabitMigration` finds the leftover rows *by*: a store seeded by
    /// a build that shipped the feature holds habits with a value in here, and
    /// nothing else on the row says so.
    var timesPerDay: Int = 0
    /// Retained so the stored schema does not change. The app committed to a
    /// single colour, so nothing reads this; dropping the column would be a
    /// migration for no gain.
    var accentRaw: String = ""
    /// When this habit was made — or `Habit.unknownCreation`, which means
    /// **unknown** rather than the year 1.
    ///
    /// The default is nobody's choice of date. Every property here carries one
    /// so that a later CloudKit sync is a change of configuration rather than a
    /// migration (see the note above the type), and a row written before this
    /// column existed reads back with whatever default the column declares.
    /// `.distantPast` is that default, and all it says is *this row predates the
    /// column*.
    ///
    /// **A sentinel is not a date, and must never become one** (#186). It is
    /// smaller than every real value, so anything taking a minimum over
    /// creation dates picks it first and answers with the year 1 —
    /// `HabitStore.earliestRecordedDay` did exactly that, and the week pager
    /// over it was bounded only by a cap that existed to survive this.
    /// Ask `hasKnownCreation` rather than comparing against `.distantPast` at
    /// the call site.
    var createdAt: Date = Date.distantPast

    /// The weekly target this habit was made with, or nil when that was never
    /// recorded.
    ///
    /// **Credit is frozen at creation and can only shrink** (#343). A habit made
    /// on a Friday has not failed the Monday it did not exist for, so it is
    /// granted the minimum credit that avoids a ✕ — and an *upward* target edit
    /// must not enlarge that grant, because an edit gets no amnesty. Deciding
    /// that needs the target as it was, which the current one cannot answer
    /// once it has moved.
    ///
    /// **Optional rather than a sentinel, deliberately** (#186). `createdAt`
    /// carries `Date.distantPast` for *unknown* and that cost a bug: a `min()`
    /// over creation dates picked the year 1 and the week pager ran to
    /// antiquity. `nil` cannot be mistaken for a target of zero — the compiler
    /// makes every reader say what absence means, and here it means *no credit
    /// claim*, which is the honest answer for a row written before this column
    /// existed. It is also what SwiftData adds by lightweight migration and
    /// what CloudKit's optional-or-defaulted rule accepts, so the stored shape
    /// stays sync-ready the way the note above the type asks.
    var targetAtCreation: Int?
    var sortOrder: Int = 0

    /// What `createdAt` holds when the row has no creation date on record.
    ///
    /// Named rather than spelled `.distantPast` where it is used, so that the
    /// comparison reads as *is this known* instead of *is this the year 1*.
    static let unknownCreation = Date.distantPast

    /// Whether `createdAt` is a date rather than the sentinel.
    ///
    /// `>` rather than `!=`: the sentinel is the earliest value the column can
    /// hold, so this also rejects anything that has somehow landed below it,
    /// and it is the same comparison the store's fetch predicate makes.
    var hasKnownCreation: Bool { createdAt > Habit.unknownCreation }

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
        // Recorded here rather than at each call site, so a habit cannot be
        // made without it. A spacer has no cadence to freeze.
        self.targetAtCreation = isSpacer ? nil : frequency.weeklyTarget
    }

    /// The cadence, read off the two columns that store it.
    ///
    /// A row left over from the per-day kind — `timesPerDay > 0` — reads back as
    /// whatever weekly cadence its other columns hold, because those were never
    /// cleared when it was switched to per-day. It is not drawn from a nonsense
    /// value; it is drawn from the cadence it had before, which is the same
    /// answer switching the kind back used to give. `DailyHabitMigration`
    /// deletes those rows at launch, so this is what the widget sees in the
    /// window before that runs and nowhere else.
    var frequency: Frequency {
        get { isDaily ? .daily : Frequency(timesPerWeek: timesPerWeek) }
        set {
            timesPerDay = 0
            switch newValue {
            case .daily:
                isDaily = true
            case .timesPerWeek(let count):
                isDaily = false
                timesPerWeek = count
            }
        }
    }

    /// What every habit-shaped surface fetches.
    ///
    /// The clause is unchanged and it is deliberately not `true` (#209). It used
    /// to be the *kind* discriminator — the weekly cadences and the blank rows
    /// holding their positions, as against Today's per-day habits — and with the
    /// per-day kind gone there is nothing left for it to exclude except the rows
    /// that kind wrote. Those rows are real: an install updating from a build
    /// that shipped the feature holds them until `DailyHabitMigration` runs, and
    /// **the widget's process never runs it**, so a home screen that redraws
    /// before the app is next opened would otherwise show habits the app no
    /// longer has a screen for.
    ///
    /// So this is a residue filter now, not a kind, and the name says the side
    /// it keeps rather than the split it used to make. It can go when
    /// `DailyHabitMigration` does, and not before.
    static let weekly = #Predicate<Habit> { $0.timesPerDay == 0 }

    /// How many completions fall on each civil day that has any.
    ///
    /// **The one place rows become history**, and the only one that reads
    /// `Completion` at all. Everything below is a projection of this small
    /// dictionary, which is deliberate on two counts: the identity stays
    /// zone-free right up to the moment something has to draw it, and the
    /// expensive half — a fetch and a reduce over every row a habit has — is one
    /// value that depends on nothing but the store, where a projection keyed by
    /// a calendar is not, because the calendar can change under it.
    ///
    /// This said the identity half was the seam a cache belongs behind. **It is
    /// not cached** (#135): a second context writes this store —
    /// `MarkHabitIntent`, on a per-tap container of its own — and never says
    /// so, so nothing here can know when to let go. What the expensive half
    /// got instead is a bound — see `Habit.dayCounts(of:within:in:)`, which is
    /// what a surface drawing a week or a month or a year calls, and which reads
    /// those days rather than all of them.
    ///
    /// A weekly-cadence habit only ever reaches one per day, so in a shipped
    /// build every value here is one. It is a count and not a set because a day
    /// **can** hold more than one row: the per-day kind put several there while
    /// it shipped (#209), and a store written before this migration can still
    /// hold a legacy double from the day-identity bug (#130). Both are seen as
    /// the number they are rather than flattened on the way in.
    ///
    /// A completion is its own row rather than a number on the habit for a
    /// reason that outlives the per-day kind: rows merge when two devices sync,
    /// and a counter is last-writer-wins.
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
    /// The rows go out from under it because **a second context writes this
    /// store**. `MarkHabitIntent` opens its own `ModelContainer` against the
    /// same App Group file — in the app's process, since `LiveActivityIntent`
    /// (#58), which changes nothing here: peer containers do not notify each
    /// other or merge their cached relationships. Since #465 the intent does
    /// post a process-local signal that makes subscribed views fetch fresh
    /// bounded snapshots, but the context and this cached array remain peers;
    /// the signal does not make either one safe to trust.
    ///
    /// So this reads through the context instead. A fetch cannot hand back a
    /// row that is already gone, which sidesteps cross-context invalidation
    /// rather than pretending the app-level redraw signal merged this model.
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
            isSpacer: isSpacer,
            // Nil rather than the sentinel, for the reason #186 gives about
            // `earliestRecordedDay`: a default `createdAt` means *unknown*, and
            // a row that does not know when it began must not claim to.
            createdDay: hasKnownCreation
                ? WeekCalendar.day(createdAt, calendar: calendar) : nil,
            targetAtCreation: targetAtCreation
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
    /// that fetched a filtered list gets counts for exactly that list.
    ///
    /// **This is not a cache and nothing here is remembered** — see
    /// `snapshots(of:within:calendar:)` for why not.
    static func dayCounts(
        of habits: [Habit], within days: ClosedRange<DayID>? = nil, in context: ModelContext
    ) -> [UUID: [DayID: Int]] {
        (try? fetchedDayCounts(of: habits, within: days, in: context)) ?? [:]
    }

    /// The same counts, with the fetch failure kept (#282).
    ///
    /// `dayCounts` above swallows a failed fetch into an empty dictionary,
    /// which is the right degradation for a grid mid-render — a frame with the
    /// marks missing beats a frame that never arrives — and the wrong one
    /// everywhere the counts *are* the answer: the export, where an empty
    /// dictionary silently becomes a file missing somebody's history, and the
    /// widget stores, where it becomes "No habits yet" about a store that
    /// merely failed to answer. Those callers use this and decide at their own
    /// boundary.
    static func fetchedDayCounts(
        of habits: [Habit], within days: ClosedRange<DayID>? = nil, in context: ModelContext
    ) throws -> [UUID: [DayID: Int]] {
        let wanted = Set(habits.map(\.id))
        guard !wanted.isEmpty else { return [:] }
        var descriptor = FetchDescriptor<Completion>(predicate: rowsFalling(in: days))
        // Fault the habit each row points at in the same pass. Without this
        // the group below asks for it row by row, which trades n fetches of
        // completions for rather more fetches of habits.
        descriptor.relationshipKeyPathsForPrefetching = [\.habit]
        let rows = try context.fetch(descriptor)

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
    /// widget's tap intent opens its own container against the same App Group
    /// file. Its process-local signal redraws the subscribed app surfaces; it
    /// does not give a model-owned cache a complete invalidation contract, nor
    /// does it cross into the widget process. So the pass is shared within one
    /// render and dropped at the end of it, which is a cost the *number of
    /// habits* no longer multiplies.
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

    /// Snapshots whose fetch failure reaches the caller (#282).
    ///
    /// `snapshots(of:within:calendar:)` above degrades a failed completion
    /// fetch into snapshots with no history, because a grid mid-render has
    /// nothing better to do with the error. Two callers do: the export, whose
    /// whole contract is that the file holds everything or does not exist, and
    /// the widget stores, which must render *unavailable* rather than a
    /// plausible emptiness. Both build from this one throwing pass.
    ///
    /// No range means all of it — the export's case — through the same shared
    /// fetch; the measured equality between one shared fetch and one per habit
    /// (see `dayCounts`) is what makes that the same cost as before. Fixtures
    /// — habits with no context — carry their rows in the cached array, where
    /// there is nothing to fetch and nothing to fail.
    static func fetchedSnapshots(
        of habits: [Habit],
        within days: ClosedRange<DayID>? = nil,
        calendar: Calendar = WeekCalendar.calendar
    ) throws -> [HabitSnapshot] {
        guard let context = habits.lazy.compactMap(\.modelContext).first else {
            return habits.map { $0.snapshot(calendar: calendar) }
        }
        let counts = try fetchedDayCounts(of: habits, within: days, in: context)
        return habits.map { habit in
            habit.snapshot(dayCounts: counts[habit.id] ?? [:], calendar: calendar)
        }
    }
}
