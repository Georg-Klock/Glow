import Foundation

/// Whether a write just met a habit's goal.
///
/// **The goal, not each repetition.** The twelfth glass of water, not each of
/// the twelve; the week's second run, not both of them. That is what keeps the
/// moment rare enough to mean anything — firing on every completion would put
/// twenty of these a day on a screen whose whole argument is that it says one
/// thing.
///
/// Exactly met, not met-or-past. A fourth completion on a three-a-week habit is
/// past the goal and fires nothing: the goal was already met, and it was met
/// once. That also removes the need to know what the count was before the
/// write — if it equals the target now, this write is the one that got there.
///
/// Pure, per the `WeekGrid` / `SlotLayout` pattern.
enum GoalMet {
    /// The goal a habit is counted against, and over what.
    static func target(of frequency: Frequency) -> Int {
        switch frequency {
        case .daily: Frequency.daysInWeek
        case .timesPerWeek(let n): n
        case .timesPerDay(let n): n
        }
    }

    /// True when this habit's count has just reached its goal exactly.
    ///
    /// A per-day habit counts today; everything week-shaped counts the week —
    /// a daily habit included, whose goal is a perfect seven.
    static func justMet(
        habit: HabitSnapshot,
        in week: Week,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Bool {
        guard !habit.isSpacer else { return false }
        let day = WeekCalendar.day(today, calendar: calendar)
        let goal = target(of: habit.frequency)
        guard goal > 0 else { return false }

        switch habit.frequency {
        case .timesPerDay:
            return habit.count(on: day) == goal
        case .daily, .timesPerWeek:
            return habit.completedDays.count { week.contains($0) } == goal
        }
    }
}
