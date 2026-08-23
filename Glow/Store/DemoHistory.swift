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
/// That exactness is the design constraint here, and it is why removal deletes
/// by provenance rather than by recomputing which days "look seeded" — a
/// recomputation would have to guess whether a completion on a matching day was
/// invented or earned, and a demo that can delete real data is worse than no
/// demo.
///
/// **The provenance is on the row** (`Completion.demoSessionID`), saved in the
/// same transaction as the row. It used to be a list of ids in the App Group
/// defaults, written *after* the completions were saved, and the gap between
/// those two writes was a real failure: a crash in it left invented history in
/// the store that nothing could name, so the toggle read as off while ten weeks
/// of fiction stayed on the grid for good. One store, one write, no gap (#140).
///
/// The toggle's state is still derived rather than stored: "is the demo in" is
/// answered by asking the store what it holds.
@MainActor
struct DemoHistory {
    /// Where the seeded ids used to be recorded. Read once per install, to
    /// move that record onto the rows it describes, and then deleted. Never
    /// written — see `adoptLegacyRecord`.
    static let legacyIDsKey = "demoHistoryCompletionIDs"

    /// Every row any demo invented. The whole of what removal takes out, and
    /// the whole of what "the demo is in" means.
    private static let invented = #Predicate<Completion> { $0.demoSessionID != nil }

    private let context: ModelContext
    private let calendar: Calendar
    private let defaults: UserDefaults
    /// The weekday nothing is expected on, or nil for none.
    ///
    /// Read here, at the store boundary, exactly as the calendar is (#181):
    /// `SeededHistory` invents no completion on a rest day, and it is handed
    /// the answer rather than looking one up from inside the decision logic.
    private let restDay: Int?

    init(
        context: ModelContext,
        defaults: UserDefaults = GlowSettings.store,
        calendar: Calendar = WeekCalendar.calendar,
        restDay: Int? = WeekPreferences.restDay
    ) {
        self.context = context
        self.defaults = defaults
        self.calendar = calendar
        self.restDay = restDay
    }

    /// Whether a demo is currently in, for the toggle to sit at.
    ///
    /// The tolerant reading: a store that cannot be asked reads as "no demo",
    /// because a toggle has to show something. Every path that *writes* asks
    /// `inventedCount()` instead and lets the failure through, so a fetch that
    /// failed can never be mistaken for an empty store and used to stack a
    /// second demo on top of the first.
    var isSeeded: Bool { ((try? inventedCount()) ?? 0) > 0 }

    /// How many invented rows the store holds.
    ///
    /// A counting fetch with a predicate, so the cost is the demo's own rows
    /// rather than every completion in the store — which matters exactly where
    /// it is least convenient, on the phone with years of real history on it.
    private func inventedCount() throws -> Int {
        try adoptLegacyRecord()
        return try context.fetchCount(FetchDescriptor<Completion>(predicate: Self.invented))
    }

    /// Invents a past for every real habit. A no-op while one is already in,
    /// so the toggle cannot stack two demos on top of each other.
    ///
    /// The first habit is perfect — a full streak is the thing the demo most
    /// needs on screen — and the rest cycle down to patchy so a missed day is
    /// on screen too. Each habit's days are derived from its own id, so
    /// switching the demo off and on rebuilds the same past. Today is never
    /// touched: the open slot is the one thing the app is for — and *today* is
    /// whatever the app currently believes it is, so a demo seeded under a
    /// debug override leaves the overridden day open rather than the real one
    /// (#204). That arrives as `now` from Settings rather than as this
    /// default: `now` is an *instant*, normalized by this type's own calendar,
    /// and a default of `WeekCalendar.today()` would hand a midnight taken in
    /// one calendar to a store built on another — which is a day out wherever
    /// the two disagree, and the suites here inject a UTC calendar.
    ///
    /// One save at the end, and nothing outside the store to keep in step with
    /// it: the whole seeding either lands or none of it does.
    func seed(now: Date = Date()) throws {
        guard try inventedCount() == 0 else { return }

        let today = WeekCalendar.day(now, calendar: calendar)
        let habits = try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        )

        // One id for this seeding, stamped on every row it writes. Generated
        // before the first insert so that no row can be written without one.
        let session = UUID()
        var position = 0
        for habit in habits where !habit.isSpacer {
            let days = SeededHistory.completions(
                for: habit.frequency,
                form: SeededHistory.form(at: position),
                seed: SeededHistory.seed(for: habit.id),
                today: today,
                restDay: restDay,
                calendar: calendar
            )
            position += 1

            for day in days {
                let completion = Completion(
                    day: day, habit: habit, demoSessionID: session, calendar: calendar
                )
                context.insert(completion)
                habit.completions?.append(completion)
            }
        }

        try commit()
    }

    /// Removes exactly the completions the demo added. Anything logged by
    /// hand — before, during or after the demo — survives, including taps on
    /// days the demo also filled.
    ///
    /// Fetched by provenance rather than scanned for: the query returns the
    /// invented rows and nothing else, so a store with years of real history
    /// costs no more to switch the demo off in than a fresh one.
    ///
    /// A seeding that was interrupted half-way is removable by the same call,
    /// because what it wrote carries the same mark as what it would have
    /// written next.
    func remove() throws {
        try adoptLegacyRecord()
        let invented = try context.fetch(FetchDescriptor<Completion>(predicate: Self.invented))
        guard !invented.isEmpty else { return }

        for completion in invented {
            completion.habit?.completions?.removeAll { $0.id == completion.id }
            context.delete(completion)
        }

        try commit()
    }

    /// Moves a pre-provenance demo onto the rows it describes, once.
    ///
    /// An install that switched the demo on before `demoSessionID` existed has
    /// its seeded ids in the defaults and nothing on the rows. Dropping that
    /// key unread would strand exactly the invented completions this type
    /// exists to be able to remove — the bug being fixed, handed to the people
    /// who already have it — so the list is read, stamped onto the rows in one
    /// save, and only then deleted.
    ///
    /// Safe to run again at any point: the key goes only after the save, so an
    /// interrupted adoption re-reads the same list, and stamping a row that is
    /// already stamped changes nothing that removal looks at. Ids that no
    /// longer resolve are simply not found — deleting a habit cascades its
    /// completions away, and that is not an error here.
    ///
    /// Costs one `UserDefaults` read on every install that has already been
    /// through it, which is every install after the first launch of this
    /// version.
    private func adoptLegacyRecord() throws {
        guard let recorded = defaults.stringArray(forKey: Self.legacyIDsKey) else { return }

        let ids = recorded.compactMap(UUID.init)
        if !ids.isEmpty {
            let session = UUID()
            let stranded = try context.fetch(
                FetchDescriptor<Completion>(predicate: #Predicate { ids.contains($0.id) })
            )
            for completion in stranded where completion.demoSessionID == nil {
                completion.demoSessionID = session
            }
            try commit()
        }

        defaults.removeObject(forKey: Self.legacyIDsKey)
    }

    /// Drops the pre-provenance record without adopting it.
    ///
    /// **Only correct where the rows it names are known to be gone**, which is
    /// one place: after `HabitStore.resetToDefaults` has emptied the store
    /// (#193). Everywhere else the key has to be *read* first — that is what
    /// `adoptLegacyRecord` is for, and dropping it unread is exactly the bug
    /// that method exists to avoid.
    ///
    /// Not load-bearing for the toggle, and worth saying which way round that
    /// is. "Is the demo in" is answered by `demoSessionID` on the rows now, not
    /// by this key, so a reset that deleted every completion already reads as
    /// no demo whether this runs or not. What it removes is a dead key naming
    /// fifty completions that no longer exist — untidy rather than wrong, and
    /// one line, in a call whose whole claim is that nothing is left over.
    func discardLegacyRecord() {
        defaults.removeObject(forKey: Self.legacyIDsKey)
    }

    /// Saves, or leaves the store exactly as it was.
    ///
    /// The rollback is the point. A `ModelContext` holds its pending changes
    /// after a failed save, and the next save from anywhere else in the app
    /// would commit them — so a demo that failed to write would arrive later,
    /// in pieces, on a screen that never asked for it.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
