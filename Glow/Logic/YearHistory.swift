import Foundation

/// How each day of a long stretch went, for the surfaces that show more days
/// than they can label.
///
/// This is `YearView`'s own rule, moved out of the view unchanged (#137). It
/// had to move: the year grid draws 365 days and spoke none of them, and a
/// summary that counted the days a second way would be a mirror copy — right
/// on the day it was written and free to drift from the drawing for ever
/// after. Now one function decides what a day is, the cells take their fill
/// from it, and the spoken sentence counts the same values.
///
/// Pure, per the `WeekGrid` pattern: snapshots in, verdicts out, no store and
/// no `Date()`.
enum YearHistory {
    /// How a day went.
    enum DayFill: Equatable, Sendable {
        /// Everything expected was done.
        case full
        /// Some of it.
        case partial
        /// None of it, or nothing was expected.
        case empty
        /// Not yet.
        case future
    }

    /// How a given day went, by the same rule the week grid uses.
    ///
    /// Only daily habits pin to a day, so only they can be *expected* on one: a
    /// habit due three times a week has no opinion about Tuesday, and counts
    /// only where it was actually logged. A rest day expects nothing either,
    /// and a completion sitting on one still counts — #72 stopped the week grid
    /// *drawing* it, not the history keeping it.
    static func fill(
        for day: Date,
        habits: [HabitSnapshot],
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> DayFill {
        guard day <= today else { return .future }

        var expected = 0
        var met = 0
        for habit in habits where !habit.isSpacer {
            // `count(on:)` rather than `completedDays.contains`: the set is
            // built fresh on every read, and this runs once per habit per day
            // of the year.
            let done = habit.count(on: day) > 0
            guard habit.frequency == .daily else {
                if done { met += 1; expected += 1 }
                continue
            }
            if WeekPreferences.isRestDay(day, restDay: restDay, calendar: calendar) {
                if done { met += 1; expected += 1 }
                continue
            }
            expected += 1
            if done { met += 1 }
        }

        guard expected > 0 else { return .empty }
        if met == expected { return .full }
        return met > 0 ? .partial : .empty
    }

    /// One column of the year grid: a week, in the calendar's own day order.
    static func fills(
        in week: Week,
        habits: [HabitSnapshot],
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [DayFill] {
        week.days.map {
            fill(for: $0, habits: habits, today: today, restDay: restDay, calendar: calendar)
        }
    }
}
