import Foundation

/// Which weekdays a habit due N times a week was actually logged on.
///
/// **This is the day-pinning** (#47). `WeekSpans` divides the week into N
/// shapes that say *how much*, and says nothing about when; these are the days
/// that say *when*. The two are drawn on the same row: the spans are the
/// division, and a lit dot sits on each day a completion landed.
///
/// The data was always there. `Completion.day` is stored and normalized to
/// midnight, so which weekday each completion fell on has been recoverable
/// since the first version — `WeekGrid.frequencySlots` simply counted them and
/// threw the weekday away. No model change and no migration.
///
/// Pure, per the `WeekGrid` / `SlotLayout` pattern.
enum WeekDots {
    /// The columns, 0 through 6, that carry a lit dot.
    ///
    /// **Every completion inside the week, including any past the goal.** A
    /// fourth completion on a three-a-week habit has a day even though it has
    /// no span; the row is a record of what happened, and a day that happened
    /// is lit whether or not it was owed. That also makes this independent of
    /// `target`, which is what keeps it from re-deriving span arithmetic.
    ///
    /// The rest day is the one exclusion, and it is not this type's opinion:
    /// #72 settled that the rest column draws nothing at all, a stored
    /// completion included. It still counts everywhere it counted; it is simply
    /// not drawn there, and a dot would be drawing it.
    static func columns(
        for habit: HabitSnapshot,
        in week: Week,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [Int] {
        guard !habit.isSpacer, !habit.frequency.isCountedPerDay else { return [] }
        return week.days.indices.filter { index in
            let day = week.days[index]
            return habit.completedDays.contains(day)
                && !WeekPreferences.isRestDay(day, calendar: calendar)
        }
    }
}
