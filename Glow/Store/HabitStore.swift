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
    /// The weekday nothing may be logged on, or nil for none.
    ///
    /// **Read here, once per instance, exactly as the calendar is** (#181). The
    /// store is a boundary — the last one a write crosses — so this is one of
    /// the few places the stored preference is legitimately looked up. It is
    /// deliberately *not* asked of the caller: the refusal below exists because
    /// a surface can outlive the setting it was rendered under, and a rest day
    /// supplied by that stale surface would make the guard agree with it.
    ///
    /// Every real caller builds a store per operation — `WeeklyGridView.store`
    /// is a computed property, and both intents construct one — so "once per
    /// instance" is once per write.
    private let restDay: Int?
    private static let log = Logger(subsystem: "com.georgklock.glow", category: "store")

    init(
        context: ModelContext,
        calendar: Calendar = WeekCalendar.calendar,
        restDay: Int? = WeekPreferences.restDay
    ) {
        self.context = context
        self.calendar = calendar
        self.restDay = restDay
    }

    // MARK: - Habits

    /// Adds a habit at the end of the list.
    ///
    /// **It used to fill the first blank row instead** (#129, #143), because
    /// `delete` left one behind and the pair kept a row's existence stable
    /// while only its contents changed. #257 reversed that: a delete collapses
    /// its row now, so there is no automatic blank row for this to consume, and
    /// consuming a *deliberate* one — the blank rows `addSpacer` makes, which
    /// are the grouping — would take away the separator somebody put there.
    ///
    /// So this appends, always. See the 2026-08-24 entry in
    /// `docs/decisions.md`.
    @discardableResult
    func addHabit(
        name: String,
        icon: String,
        frequency: Frequency,
        now: Date = Date()
    ) throws -> Habit {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let habit = Habit(
            name: trimmed,
            icon: icon,
            frequency: frequency,
            createdAt: now,
            sortOrder: try nextSortOrder()
        )
        context.insert(habit)
        try commit()
        return habit
    }

    /// Appends a whole list of rows as one transaction, in the order given.
    /// Returns how many were added.
    ///
    /// **One save, not one per row**, and that is the whole reason this exists
    /// rather than a loop over `addHabit` (#140). A list committed row by row
    /// is a list that can be interrupted half-way, and what it leaves behind is
    /// a set of habits nobody chose — the first four of a design, say — which
    /// the caller then has to be able to tell apart from a list somebody
    /// edited down to four. Either the whole list is there or none of it is,
    /// so "did this install get its defaults" stays a question with an answer.
    ///
    /// Blank rows are inserted as blank rows: a template that says spacer
    /// carries no name, icon or cadence into the store, whatever else it holds.
    ///
    /// The blank-row filling `addHabit` does is deliberately not applied here.
    /// These rows arrive with their own positions and their own gaps, and
    /// dropping the first of them into a gap that a previous one just made
    /// would rearrange the list on its way in.
    @discardableResult
    func addAll(_ templates: [DefaultHabits.Template], now: Date = Date()) throws -> Int {
        guard !templates.isEmpty else { return 0 }

        insert(templates, from: try nextSortOrder(), now: now)
        try commit()
        return templates.count
    }

    /// Turns templates into rows, numbered from `start`, and saves nothing.
    ///
    /// Split out of `addAll` so that `resetToDefaults` can put the same list in
    /// **inside a transaction that also empties the store** — a save between
    /// the delete and the insert is a window in which the store holds nothing,
    /// which is the half-seeded state #140 exists to make impossible, wearing
    /// its worst face.
    ///
    /// The starting number is a parameter for the same reason: after the
    /// deletes are staged, `nextSortOrder` would be answering from rows that
    /// are on their way out, so the caller that knows the store is being
    /// emptied says zero instead of asking.
    private func insert(_ templates: [DefaultHabits.Template], from start: Int, now: Date) {
        var order = start
        for template in templates {
            let habit = Habit(
                name: template.isSpacer
                    ? "" : template.name.trimmingCharacters(in: .whitespacesAndNewlines),
                icon: template.isSpacer ? "" : template.icon,
                frequency: template.isSpacer ? .daily : template.frequency,
                createdAt: now,
                sortOrder: order,
                isSpacer: template.isSpacer
            )
            context.insert(habit)
            order += 1
        }
    }

    /// Throws away everything the store holds and puts the current defaults in.
    /// Returns how many habits were added.
    ///
    /// **The only way the defaults ever go in**, from either of two taps: the
    /// typed, destructive Reset to Default Habits in Settings (#193), and the
    /// empty state's "Start with a Pre-Selected Set" on a store that holds
    /// nothing (#228). It was the escape hatch from first-run seeding's guard
    /// before that seeding existed; now there is no other door, and it is
    /// destructive on purpose: not a merge, not a reconciliation by name, a
    /// return to zero.
    ///
    /// Which is why the empty state can call it unguarded. Destructive is a
    /// claim about what the store held, and that caller is only ever offered
    /// when it held nothing.
    ///
    /// **One transaction.** Every delete and every insert is staged and then
    /// committed once, so a failure anywhere leaves the store exactly as it
    /// was — with the person's habits still in it. That is the property #140
    /// established for seeding and it matters more here, because the thing a
    /// half-finished run would be half-way through is a deletion.
    ///
    /// Completions are deleted explicitly rather than left to the `.cascade`
    /// rule. The cascade does reach every completion that is attached to a
    /// habit, which is all of them in a healthy store — but the whole promise
    /// of this call is that nothing survives it, and a completion whose habit
    /// reference is nil would survive a cascade. Saying it outright costs one
    /// fetch and removes the word "should" from the promise.
    ///
    /// There is no first-run flag left to keep in step (#228). One used to
    /// record whether this install had ever been seeded, and this call
    /// deliberately left it alone; with nothing seeding by itself, an empty
    /// store means one thing and the flag had nothing left to say.
    @discardableResult
    func resetToDefaults(now: Date = Date()) throws -> Int {
        for completion in try context.fetch(FetchDescriptor<Completion>()) {
            completion.habit?.completions?.removeAll { $0.id == completion.id }
            context.delete(completion)
        }
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            context.delete(habit)
        }

        insert(DefaultHabits.all, from: 0, now: now)
        try commit()
        return DefaultHabits.all.count
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
        try commit()
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
        try commit()
    }

    /// Deleting a row removes it. Everything below moves up.
    ///
    /// **This reverses #129/#143** (#257). Deleting a habit used to blank its
    /// row in place and leave the gap behind, on the reasoning that the grid is
    /// a layout somebody arranged and collapsing a row silently rewrites the
    /// grouping of every habit under it. The gap was meant to be the honest
    /// thing to leave.
    ///
    /// In use it was not: a delete that leaves a row behind reads as a delete
    /// that did not work, and the row then has to be deleted a second time to
    /// actually go. One act, one row gone, is what a delete means. The blank
    /// rows that express grouping are still there and still deliberate —
    /// `addSpacer` makes those, and they are the only ones now. See the
    /// 2026-08-24 entry in `docs/decisions.md`; the older one stays true as a
    /// record of why the other behaviour existed.
    ///
    /// **The identity goes with the row** (#129). Widget configurations and
    /// widget intents resolve habits by `id`, and a deleted habit's `id` must
    /// stop resolving to anything — which deleting the row does outright,
    /// rather than by retiring the `id` of a row that survives.
    func delete(_ habit: Habit) throws {
        try clearHistory(of: habit)
        context.delete(habit)
        try commit()
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
        try commit()
    }

    /// Saves, and then tells the widgets.
    ///
    /// Every write in this type ends here, and that is the point (#134): a
    /// reload called at the call site kept being forgotten — swipe-delete and
    /// reorder both saved without one — and a widget then showed an order or a
    /// row that no longer existed until something unrelated reloaded it. Now
    /// forgetting to invalidate means forgetting to save, which is not a
    /// mistake that survives a test run.
    ///
    /// `WidgetRefresh` coalesces, so a reorder rewriting `sortOrder` on ten
    /// rows still costs one reload.
    ///
    /// A failed save rolls back (#140). A `ModelContext` keeps its pending
    /// changes when a save throws, and the next save from anywhere else in the
    /// app commits them — so a write that was reported as failed would arrive
    /// later, out of order, attached to an unrelated gesture. Leaving the store
    /// as it was is the only outcome a caller can do anything with.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        WidgetRefresh.invalidate()
    }

    private func nextSortOrder() throws -> Int {
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let highest = try context.fetch(descriptor).first?.sortOrder
        return (highest ?? -1) + 1
    }

    // MARK: - Completions

    /// What a write attempt did.
    ///
    /// A refusal is an outcome rather than an error, because it is the rule
    /// working: the rest day refusing a write is not a failure of anything.
    enum ToggleOutcome: Equatable {
        case completed
        case uncompleted
        /// The day was already in the state that was asked for, so nothing was
        /// written (#272, #292).
        ///
        /// Only `setCompletion` can return this, and it is the whole point of
        /// that method: a second delivery of the same request is a no-op rather
        /// than a reversal. `toggleCompletion` always asks for the opposite of
        /// what it found, so it never sees this.
        case unchanged
        /// Nothing was logged and nothing removed. The rest day, a day still to
        /// come, a blank row, or a habit this surface does not own.
        case refused
    }

    /// Whether this row can take a day-shaped write at all.
    ///
    /// Two rejections, and both are about a caller that is out of date rather
    /// than a caller that is wrong (#129). A widget renders in its own process
    /// and its snapshot can outlive the thing it draws, so a tap can arrive for
    /// a habit that has since been deleted — now a blank row — or for one the
    /// app no longer draws at all. The store is the one path both processes
    /// share, so the rule lives here rather than in trust that no button was
    /// offered.
    ///
    /// The second clause is now about the per-day rows #209 left behind, and it
    /// is the same clause it always was: a row with a per-day count on it has no
    /// surface in this build, and a tap landing on one would write history onto
    /// a habit on its way out. It goes when `DailyHabitMigration` does.
    private func acceptsDayWrite(_ habit: Habit) -> Bool {
        !habit.isSpacer && habit.timesPerDay == 0
    }

    /// This habit's completions on one civil day, fetched rather than
    /// remembered.
    ///
    /// **A fetch, for the same reason `Habit.liveCompletions` is one** (#145):
    /// the cached `completions` array can be missing a row the widget's process
    /// wrote and can be holding one it deleted. On a read that only cost a
    /// wrong number; here it decides whether a tap creates a row or removes
    /// one, so a stale array is how a day ends up with two completions on it.
    ///
    /// Filtered in memory rather than by a predicate on `dayKey`, because a
    /// legacy row's key is empty and its day is inferred — a predicate would
    /// silently skip exactly the rows #130 is about. Once a store has been
    /// through `StoreMigration.stampDayIdentities` the predicate could be
    /// pushed down; that is #135's to take, and it needs a way to know the
    /// store is fully stamped, which the migration record now says.
    private func completions(of habit: Habit, on dayID: DayID) throws -> [Completion] {
        let habitID = habit.id
        let descriptor = FetchDescriptor<Completion>(
            predicate: #Predicate { $0.habit?.id == habitID }
        )
        return try context.fetch(descriptor).filter { $0.dayID == dayID }
    }

    /// Marks the habit done on `date`, or un-marks it if it already is.
    ///
    /// Idempotent in the sense that the stored state only ever has zero or one
    /// completion per day: a duplicate cannot be created by tapping twice
    /// quickly, because the second tap finds the first one and removes it.
    ///
    /// **Any day, and that is the point** (#116). This has always taken an
    /// arbitrary date; what changed is that the week view now offers days other
    /// than today. `allowingFuture` defaults to false, so the widget's intents
    /// get the strict answer without having to name it, and only the week view
    /// — with demo history in — opts out.
    ///
    /// **Every row on the day goes, not the first one found** (#130). A store
    /// written by a build before day identities can hold two rows for one civil
    /// day — that is the bug's own residue, a completion logged in Berlin and
    /// logged again after landing in Los Angeles — and leaving one behind would
    /// make the slot flicker back to done on the next redraw. Un-marking a day
    /// means the day is not marked.
    @discardableResult
    /// Flips a day's completion. The app's own surfaces use this, because they
    /// are never stale: they redraw in-process from the store they just wrote.
    ///
    /// **A widget must not use it** — see `setCompletion`, which is what the
    /// widget's marks call and why.
    func toggleCompletion(
        for habit: Habit,
        on date: Date,
        allowingFuture: Bool = false
    ) throws -> ToggleOutcome {
        // Read, then ask for the opposite. The guards live once, in
        // `setCompletion`, and a toggle is the degenerate case of a set.
        let isDone = !(try completions(of: habit, on: DayID(date, calendar: calendar))).isEmpty
        return try setCompletion(
            for: habit, on: date, done: !isDone, allowingFuture: allowingFuture
        )
    }

    /// Puts a day's completion into the state asked for, and says whether that
    /// changed anything.
    ///
    /// **Idempotent, and that is the point** (#272, #292). The widget's marks
    /// call this rather than `toggleCompletion`, because a toggle is a
    /// *relative* operation and a widget is a surface that can be both stale
    /// and delivered twice:
    ///
    /// * **Delivered twice.** A single tap has been measured performing the
    ///   intent twice, 13ms apart, on an iPhone 14 Pro. Under a toggle the
    ///   second performance undid the first and the tap did nothing; under a
    ///   set it finds the day already in the requested state and writes
    ///   nothing.
    /// * **Stale.** WidgetKit's pixels can lag the store by seconds, so
    ///   somebody taps what is drawn as an open ring on a day the store already
    ///   has as done. A toggle reads that as "flip it" and *removes* a
    ///   completion they were trying to make. A set reads the ring as the
    ///   request it was — "make this done" — and the record survives.
    ///
    /// Both failures were the same complaint: checking habits off quickly
    /// un-does them. The asymmetry is what settles the design — the worst a
    /// set can do is nothing, and the worst a toggle can do is silently retract
    /// a completion.
    ///
    /// `done` is the state the *rendered control* was asking for, not the
    /// state the store is believed to be in. The call sites pass the complement
    /// of what they drew.
    func setCompletion(
        for habit: Habit,
        on date: Date,
        done: Bool,
        allowingFuture: Bool = false
    ) throws -> ToggleOutcome {
        let dayID = DayID(date, calendar: calendar)
        let day = dayID.date(in: calendar)

        // A completion logged ahead is a claim about something that has not
        // happened, and the app's one signal is a record of what did. Demo
        // history is the exception and says so at the call site: its whole job
        // is an invented past, and painting days ahead is the same job.
        //
        // Guarded here as well as in the grid, for the reason the rest day is:
        // a surface can outlive the setting it was built under, and this is the
        // path every surface shares.
        guard allowingFuture || day <= WeekCalendar.today(calendar: calendar) else {
            return .refused
        }

        // A rest day is true rest: nothing can be logged on it and nothing
        // un-logged. The grid withholds the tap, but the widget runs in a
        // second process and can hold a surface rendered before the setting
        // changed — so the rule lives here, on the one write path both
        // processes share, rather than in trust that no button was offered.
        // A completion already stored on a rest day stays: records of what
        // happened remain records of what happened.
        guard !WeekPreferences.isRestDay(day, restDay: restDay, calendar: calendar) else {
            return .refused
        }

        // A blank row has no habit to log, and a row the per-day kind left
        // behind has no surface at all. Either write would be a stale caller's,
        // and both used to be accepted. See `acceptsDayWrite`, #129 and #209.
        guard acceptsDayWrite(habit) else { return .refused }

        let existing = try completions(of: habit, on: dayID)
        // The idempotent step: already what was asked for, so nothing is
        // written and nothing is reported as having happened. A caller that
        // animates on `.completed` therefore animates once per real change
        // rather than once per delivery.
        guard existing.isEmpty == done else { return .unchanged }

        if !existing.isEmpty {
            let ids = Set(existing.map(\.id))
            habit.completions?.removeAll { ids.contains($0.id) }
            for completion in existing {
                context.delete(completion)
            }
            try commit()
            return .uncompleted
        }

        let completion = Completion(day: day, habit: habit, calendar: calendar)
        context.insert(completion)
        habit.completions?.append(completion)
        try commit()
        return .completed
    }

    /// The earliest day the record reaches, normalized to midnight, or nil for
    /// a store that knows nothing about when it began.
    ///
    /// The first completion on record or the first habit's creation, whichever
    /// is earlier — the demo invents completions ten weeks before the habits
    /// that carry them, so neither table alone is the answer. `WeekReach` turns
    /// it into how far the week view may be paged (#117), and since #186 that
    /// is the whole of the bound: there is no cap behind this any more.
    ///
    /// **A habit with no creation date on record does not start the record**
    /// (#186). `Habit.createdAt` defaults to `Habit.unknownCreation` for every
    /// row written before that column existed, and a sentinel that sorts before
    /// every real date is exactly what a `min` reaches for: one such row used to
    /// make the record — and the pager over it — begin in the year 1. The
    /// predicate is the *fetch's* rather than a filter after it, because
    /// `fetchLimit = 1` over an unfiltered ascending sort returns the sentinel
    /// row and hides every real date behind it.
    ///
    /// **So a store whose only signal is a sentinel answers nil**, and the
    /// pager stays on this week. That is the same answer a fresh install gets
    /// and it is the honest one: nothing is known about when this habit began,
    /// and inventing a start would be inventing a past the record does not
    /// hold. It costs a habit created before the column existed and never once
    /// logged — the one store where the old cap gave twelve weeks of reach and
    /// this gives none — and there is nothing in those weeks to correct,
    /// because there is nothing in that store at all. Its first completion is
    /// its record, from the day it is made.
    ///
    /// **A read, on the type that says reads do not go through it.** The
    /// exception is deliberate and narrow: this is a `min` over two tables, and
    /// `@Query` can only express it by fetching both of them into a view. Two
    /// sorted fetches of one row each instead. It is also not a value a view
    /// should recompute per redraw, which is why the caller holds it in state
    /// and refreshes it on the events that can move it.
    ///
    /// A fetch that fails reads as "nothing on record", which is the same
    /// answer an empty store gives and costs only the pager: the reach
    /// collapses to the current week rather than the screen failing.
    func earliestRecordedDay() -> Date? {
        var completions = FetchDescriptor<Completion>(sortBy: [SortDescriptor(\.day)])
        completions.fetchLimit = 1
        let unknown = Habit.unknownCreation
        var habits = FetchDescriptor<Habit>(
            predicate: #Predicate<Habit> { $0.createdAt > unknown },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        habits.fetchLimit = 1

        let logged = (try? context.fetch(completions))?.first?.day
        let created = (try? context.fetch(habits))?.first?.createdAt
        guard let earliest = [logged, created].compactMap({ $0 }).min() else { return nil }
        return WeekCalendar.day(earliest, calendar: calendar)
    }

    // MARK: - Counts
    //
    // A day holding more than one completion, which `toggleCompletion` cannot
    // express: it stores zero or one per day by construction.
    //
    // The per-day kind was what made such a day ordinary, and it is gone (#209)
    // — `recordTap` and the ring rule it translated went with it. What is left
    // is not ordinary but it is real: a store written before day identities can
    // hold two rows for one civil day (#130), the same habit logged in Berlin
    // and again after landing in Los Angeles. `clearDay` is how a day like that
    // is put right, and it has to remove *every* row rather than the first, so
    // `count` and `addCompletion` are how that behaviour stays testable against
    // the store rather than against a mirror of it.

    /// How many times the habit is logged on `date`.
    ///
    /// Non-throwing, so a failed fetch reads as an empty day rather than as a
    /// broken ring. The write paths below do not get that luxury.
    func count(for habit: Habit, on date: Date) -> Int {
        let dayID = DayID(date, calendar: calendar)
        return ((try? completions(of: habit, on: dayID)) ?? []).count
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
        let dayID = DayID(date, calendar: calendar)
        let completion = Completion(
            day: dayID.date(in: calendar), habit: habit, calendar: calendar
        )
        context.insert(completion)
        habit.completions?.append(completion)
        try commit()
        return try completions(of: habit, on: dayID).count
    }

    /// Removes every completion on `date`, and returns how many there were.
    @discardableResult
    func clearDay(for habit: Habit, on date: Date) throws -> Int {
        guard !habit.isSpacer else { return 0 }
        let doomed = try completions(of: habit, on: DayID(date, calendar: calendar))
        guard !doomed.isEmpty else { return 0 }

        let ids = Set(doomed.map(\.id))
        habit.completions?.removeAll { ids.contains($0.id) }
        for completion in doomed {
            context.delete(completion)
        }
        try commit()
        return doomed.count
    }

    /// Logs a failure without taking down the screen. A habit tracker that
    /// crashes on a write is worse than one that misses a tap, and the log is
    /// where a real store problem would show up.
    static func report(_ error: Error, operation: String) {
        log.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}
