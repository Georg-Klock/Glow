import Foundation

/// The three states a slot can be in. Exactly one applies to any slot.
enum SlotState: String, Equatable, Sendable {
    /// Not completed, and not actionable today. Flat, SDR, no glow.
    case inactive
    /// Today's slot, not yet completed. The only steadily glowing state.
    case open
    /// Completed. Solid colour, SDR, no glow once the animation settles.
    case filled
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
}

/// A habit reduced to the plain values the grid needs. The views and this
/// logic never touch a SwiftData model, so both stay testable without a store.
struct HabitSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var frequency: Frequency
    var accent: HabitAccent
    var completedDays: Set<Date>

    init(
        id: UUID,
        name: String,
        icon: String,
        frequency: Frequency,
        accent: HabitAccent,
        completedDays: Set<Date>
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.frequency = frequency
        self.accent = accent
        self.completedDays = completedDays
    }
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
        let todayStart = WeekCalendar.day(today, calendar: calendar)

        switch habit.frequency {
        case .daily:
            return dailySlots(habit: habit, week: week, today: todayStart)
        case .timesPerWeek(let target):
            return frequencySlots(habit: habit, week: week, today: todayStart, target: target)
        }
    }

    /// Daily rows are day-pinned: column N is weekday N, always.
    private static func dailySlots(habit: HabitSnapshot, week: Week, today: Date) -> [Slot] {
        week.days.enumerated().map { index, day in
            let isDone = habit.completedDays.contains(day)
            let isToday = day == today
            let state: SlotState = isDone ? .filled : (isToday ? .open : .inactive)
            // Past days are never editable, so only today carries an action.
            return Slot(index: index, state: state, actionDay: isToday ? day : nil)
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
