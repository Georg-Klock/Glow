import Foundation

/// The four states a slot can be in. Exactly one applies to any slot.
enum SlotState: String, Equatable, Sendable {
    /// Nothing has happened here and nothing can yet: a day still to come.
    case inactive
    /// A past day that went unlogged.
    ///
    /// Only daily habits can miss. For a habit due a number of times a week, an
    /// empty Monday is not a failure on Tuesday — the week is still winnable —
    /// so those rows never produce this state.
    case missed
    /// Today's slot, not yet completed. The only steadily glowing state.
    case open
    /// Completed.
    case filled
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
}

/// One rendered circle or pill.
struct Slot: Identifiable, Equatable, Sendable {
    let index: Int
    let state: SlotState
    /// The day a tap would toggle, or nil when the slot is not tappable.
    /// Carrying the day here keeps every calendar decision out of the views:
    /// a view taps what it is handed and never works out which day that was.
    let actionDay: Date?

    var id: Int { index }
    var isTappable: Bool { actionDay != nil }

    /// Only today's slot ever carries an action, so this is also what separates
    /// a completion made today from one made earlier in the week.
    var isToday: Bool { actionDay != nil }

    var mark: SlotMark {
        switch state {
        case .open: .openToday
        case .filled: isToday ? .doneToday : .donePast
        case .missed: .missed
        case .inactive: .upcoming
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

    init(
        id: UUID,
        name: String,
        icon: String,
        frequency: Frequency,
        completionCounts: [Date: Int],
        isSpacer: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.frequency = frequency
        self.completionCounts = completionCounts
        self.isSpacer = isSpacer
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
enum WeekGrid {
    static func slots(
        for habit: HabitSnapshot,
        in week: Week,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [Slot] {
        guard !habit.isSpacer else { return [] }
        let todayStart = WeekCalendar.day(today, calendar: calendar)

        switch habit.frequency {
        case .daily:
            return dailySlots(habit: habit, week: week, today: todayStart, calendar: calendar)
        case .timesPerWeek(let target):
            return frequencySlots(habit: habit, week: week, today: todayStart, target: target)
        case .timesPerDay:
            // A per-day habit has no week row. It is one ring on Today, and the
            // week-shaped screens filter it out before reaching here — this is
            // the backstop, so a missed filter draws nothing rather than drawing
            // a week the habit does not have.
            return []
        }
    }

    /// Daily rows are day-pinned: column N is weekday N, always.
    private static func dailySlots(
        habit: HabitSnapshot,
        week: Week,
        today: Date,
        calendar: Calendar
    ) -> [Slot] {
        week.days.enumerated().map { index, day in
            let isDone = habit.completedDays.contains(day)
            let isToday = day == today
            // A rest day is never open and never missed. Nothing was expected,
            // so nothing was skipped — it draws as an empty socket whether it
            // is behind or ahead. A completion logged on one still counts and
            // still shows; resting is permission, not a prohibition.
            let isRest = WeekPreferences.isRestDay(day, calendar: calendar)

            let state: SlotState =
                if isDone { .filled }
                else if isRest { .inactive }
                else if isToday { .open }
                else if day < today { .missed }
                else { .inactive }

            // Past days are never editable, and a rest day has nothing to
            // toggle toward, so only an expectant today carries an action.
            return Slot(index: index, state: state, actionDay: isToday && !isRest ? day : nil)
        }
    }

    /// Frequency rows are not day-pinned: pills fill left to right in the order
    /// completions are logged, and which weekday each landed on is not recorded
    /// in the layout at all.
    private static func frequencySlots(
        habit: HabitSnapshot,
        week: Week,
        today: Date,
        target: Int
    ) -> [Slot] {
        let completionsThisWeek = habit.completedDays.count { week.contains($0) }
        // A habit edited from 5x down to 3x can hold more completions than it
        // has pills. Clamp rather than draw a row that overflows its own goal.
        let filledCount = min(completionsThisWeek, target)

        let todayIsInWeek = week.contains(today)
        let doneToday = habit.completedDays.contains(today)

        // Open only when the goal is still reachable and today is unspent.
        let openIndex: Int? = (todayIsInWeek && !doneToday && filledCount < target) ? filledCount : nil
        // If today is already logged, its pill is the last filled one, since
        // pills fill in completion order and today is the most recent day.
        let undoIndex: Int? = (todayIsInWeek && doneToday && filledCount > 0) ? filledCount - 1 : nil

        return (0..<target).map { index in
            let state: SlotState =
                index < filledCount ? .filled : (index == openIndex ? .open : .inactive)
            let isTappable = index == openIndex || index == undoIndex
            return Slot(index: index, state: state, actionDay: isTappable ? today : nil)
        }
    }
}
