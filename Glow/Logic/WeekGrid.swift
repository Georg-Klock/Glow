import Foundation

/// The five states a slot can be in. Exactly one applies to any slot.
enum SlotState: String, Equatable, Sendable {
    /// Nothing has happened here and nothing can yet: a day still to come.
    case inactive
    /// A day, or a rep, that can no longer happen.
    ///
    /// For a daily habit that is a past day that went unlogged. For a habit due
    /// a number of times a week it is a rep with no day left to land on — an
    /// empty Monday is still not a failure on Tuesday, and it becomes one once
    /// no day remains that could have carried it. The week is winnable right up
    /// until it is not, and this is the state for after that (#82).
    ///
    /// Never a warning. `WeekSpans` decides it with a strict inequality —
    /// `repsLeft > actionableLeft` — so a rep is only lost when the days have
    /// actually run out, not when they are about to.
    case missed
    /// Today's slot, not yet completed. The only steadily glowing state.
    case open
    /// Completed.
    case filled
    /// The rest day: a day nothing can happen on, which is not the same as a
    /// day that has not happened yet.
    ///
    /// It was `.inactive` until #72, which drew a socket on it — a socket says
    /// *one is coming*, and on a rest day none is. This state wins over every
    /// other, a stored completion included: the completion still counts
    /// everywhere it counted before, it simply is not drawn in the week grid.
    /// See docs/decisions.md.
    case rest
}

/// What a slot actually draws.
///
/// `SlotState` says what is true; this says what is shown, and the two differ in
/// one place: a completion today and a completion on Monday are the same state
/// and not the same mark. Derived here rather than in a view so the mapping is
/// testable without a renderer, and so the app and the widget cannot disagree
/// about it.
enum SlotMark: Equatable, Sendable {
    /// Today, still undone. A glowing ring — the one thing on screen asking for
    /// anything.
    case openToday
    /// Today, done. A glowing checkmark.
    case doneToday
    /// Done, on a day already gone.
    case donePast
    /// A daily habit's past day that went unlogged.
    case missed
    /// A day still to come.
    case upcoming
    /// The rest day. Drawn as nothing at all — the column keeps its width and
    /// holds no mark, so the line down it is the only thing in it.
    case rest
}

/// One rendered circle or pill.
struct Slot: Identifiable, Equatable, Sendable {
    let index: Int
    let state: SlotState
    /// The day a tap would toggle, or nil when the slot is not tappable.
    /// Carrying the day here keeps every calendar decision out of the views:
    /// a view taps what it is handed and never works out which day that was.
    let actionDay: Date?

    /// Whether this slot stands for today.
    ///
    /// A real comparison, made by the grid, rather than the alias for
    /// `actionDay != nil` it used to be. That alias was true only while today
    /// was the one day that carried an action; the week view now hands six more
    /// days one, and a Monday completion would have started drawing itself as
    /// today's (#116).
    let isToday: Bool

    var id: Int { index }
    var isTappable: Bool { actionDay != nil }

    var mark: SlotMark {
        switch state {
        case .open: .openToday
        case .filled: isToday ? .doneToday : .donePast
        case .missed: .missed
        case .inactive: .upcoming
        case .rest: .rest
        }
    }
}

/// A habit reduced to the plain values the grid needs. The views and this
/// logic never touch a SwiftData model, so both stay testable without a store.
struct HabitSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var frequency: Frequency
    /// How many completions fall on each day that has any.
    ///
    /// A count rather than a set of days, because a per-day habit can be logged
    /// several times on one. Everything week-shaped reads `completedDays` and
    /// cannot tell the difference.
    var completionCounts: [Date: Int]
    /// A blank row held in the order to group the habits around it. Draws
    /// nothing and is never counted as due, done or missed.
    var isSpacer: Bool
    /// The midnight this habit was made, or nil when that is not known.
    ///
    /// **A day before this is not a day that was missed** (#265). It used to be
    /// absent here, so a week earlier than the habit drew a ✕ on every column —
    /// the app asserting a failure on days when there was nothing to fail. A ✕
    /// means "this became unavoidable" (#82), and nothing becomes unavoidable
    /// before it is asked for.
    ///
    /// Nil is *unknown*, not *the beginning of time*: `Habit.createdAt` defaults
    /// to `Habit.unknownCreation` for every row written before that column
    /// existed, and #186 established that such a row must not be trusted to
    /// bound anything. An unknown creation means every day is treated as after
    /// it, which is exactly the behaviour that shipped before this existed.
    var createdDay: Date?

    init(
        id: UUID,
        name: String,
        icon: String,
        frequency: Frequency,
        completionCounts: [Date: Int],
        isSpacer: Bool = false,
        createdDay: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.frequency = frequency
        self.completionCounts = completionCounts
        self.isSpacer = isSpacer
        self.createdDay = createdDay
    }

    /// Whether the habit existed on `day`. True when the creation day is
    /// unknown — see `createdDay`.
    func existed(on day: Date) -> Bool {
        guard let createdDay else { return true }
        return day >= createdDay
    }

    /// A habit whose days are done or not done, which is every weekly cadence.
    init(
        id: UUID,
        name: String,
        icon: String,
        frequency: Frequency,
        completedDays: Set<Date>,
        isSpacer: Bool = false
    ) {
        self.init(
            id: id,
            name: name,
            icon: icon,
            frequency: frequency,
            completionCounts: completedDays.reduce(into: [:]) { $0[$1] = 1 },
            isSpacer: isSpacer
        )
    }

    /// Every day with at least one completion.
    var completedDays: Set<Date> { Set(completionCounts.keys) }

    /// How many times the habit was logged on `day`.
    func count(on day: Date) -> Int { completionCounts[day] ?? 0 }
}

/// Turns a habit plus a week into the row of slots to draw.
///
/// The whole interaction model of the app is one rule, enforced here: at most
/// one slot per habit is open, and only ever for the current day.
///
/// **What is open and what is editable are two questions** (#116). Exactly one
/// slot is ever open, on today, on every surface — that has not moved. Which
/// slots respond to a tap is the surface's business, and `SlotEditing` is how
/// the surface says so.
enum WeekGrid {
    /// `restDay` is the weekday nothing is expected on, or nil for none. A
    /// parameter, like the calendar, rather than a read of `WeekPreferences`
    /// (#181) — the caller has already read it once at its own boundary.
    static func slots(
        for habit: HabitSnapshot,
        in week: Week,
        today: Date,
        editing: SlotEditing,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [Slot] {
        guard !habit.isSpacer else { return [] }
        let todayStart = WeekCalendar.day(today, calendar: calendar)

        switch habit.frequency {
        case .daily:
            return dailySlots(
                habit: habit, week: week, today: todayStart,
                editing: editing, restDay: restDay, calendar: calendar
            )
        case .timesPerWeek(let target):
            return frequencySlots(
                habit: habit, week: week, today: todayStart, target: target,
                restDay: restDay, calendar: calendar
            )
        }
    }

    /// Daily rows are day-pinned: column N is weekday N, always.
    private static func dailySlots(
        habit: HabitSnapshot,
        week: Week,
        today: Date,
        editing: SlotEditing,
        restDay: Int?,
        calendar: Calendar
    ) -> [Slot] {
        week.days.enumerated().map { index, day in
            let isDone = habit.completedDays.contains(day)
            let isToday = day == today
            // A rest day is never open, never missed, and never writable. It
            // is true rest — the week stops there rather than being made up
            // around it — so it draws nothing at all, whether it is behind or
            // ahead, and it never carries an action. Only new writes are
            // refused, and the refusal itself is `HabitStore.toggleCompletion`'s;
            // withholding the tap here is the same rule at the surface.
            //
            // Rest is tested *before* `isDone`, which is the one clause of #39
            // that #72 reverses: a completion already on record still counts —
            // `completedDays` is untouched, weekly totals are untouched,
            // History still shows it — but the week grid stops drawing it. The
            // grid's job is to say what is open, and on a rest day that is
            // nothing.
            let isRest = WeekPreferences.isRestDay(day, restDay: restDay, calendar: calendar)

            // A day before the habit existed is `.inactive`, never `.missed`
            // (#265): it draws the unlit dot a day still to come draws, which
            // is the honest mark for a day nothing was ever asked of. The
            // ordering matters — a completion still wins, because a day can
            // carry one from an import or a store older than the column.
            let state: SlotState =
                if isRest { .rest }
                else if isDone { .filled }
                else if isToday { .open }
                else if day < today { habit.existed(on: day) ? .missed : .inactive }
                else { .inactive }

            // Which days carry an action is the surface's answer, not this
            // grid's: the week view edits any day it shows, the widget and the
            // month edit today. `SlotEditing` refuses the rest day on both, so
            // the clause that used to be written out here lives in one place.
            return Slot(
                index: index,
                state: state,
                actionDay: editing.day(
                    atColumn: index, in: week, today: today,
                    restDay: restDay, calendar: calendar
                ),
                isToday: isToday
            )
        }
    }

    /// Frequency rows are not day-pinned: pills fill left to right in the order
    /// completions are logged, and which weekday each landed on is not recorded
    /// in the layout at all.
    ///
    /// **`SlotEditing` does not reach here, and that is not an oversight.** A
    /// pill is not a day, so there is no past day in this row for a surface to
    /// widen to. The day-shaped editing of an N×/week habit happens on the
    /// spans — `WeekSpans`, where a column under a finger *is* a weekday — and
    /// these pills keep the one action they ever had: today's, or the undo of
    /// today's. `MonthGrid` asks this function exactly that question.
    private static func frequencySlots(
        habit: HabitSnapshot,
        week: Week,
        today: Date,
        target: Int,
        restDay: Int?,
        calendar: Calendar
    ) -> [Slot] {
        let completionsThisWeek = habit.completedDays.count { week.contains($0) }
        // A habit edited from 5x down to 3x can hold more completions than it
        // has pills. Clamp rather than draw a row that overflows its own goal.
        let filledCount = min(completionsThisWeek, target)

        let todayIsInWeek = week.contains(today)
        let doneToday = habit.completedDays.contains(today)
        // A rest day stops frequency rows too: the pill that would be open
        // waits, unlit, and the undo waits with it. Not day-pinned does not
        // mean not day-bound — the only day a tap can ever touch is today,
        // and on the rest day today refuses.
        let todayRests = WeekPreferences.isRestDay(today, restDay: restDay, calendar: calendar)

        // Open only when the goal is still reachable and today is unspent.
        let openIndex: Int? =
            (todayIsInWeek && !todayRests && !doneToday && filledCount < target) ? filledCount : nil
        // If today is already logged, its pill is the last filled one, since
        // pills fill in completion order and today is the most recent day.
        let undoIndex: Int? =
            (todayIsInWeek && !todayRests && doneToday && filledCount > 0) ? filledCount - 1 : nil

        return (0..<target).map { index in
            let state: SlotState =
                index < filledCount ? .filled : (index == openIndex ? .open : .inactive)
            // The open pill and the pill holding today's completion are the two
            // that stand for today; the rest stand for whichever day happened
            // to fill them, which this row does not record.
            let isTappable = index == openIndex || index == undoIndex
            return Slot(
                index: index,
                state: state,
                actionDay: isTappable ? today : nil,
                isToday: isTappable
            )
        }
    }
}
