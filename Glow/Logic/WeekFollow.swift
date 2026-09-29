import Foundation

/// Which week This Week shows once the calendar under it has moved.
///
/// Two things move it without anybody touching the pager: today crossing into
/// a new week, and the week start changing in Settings. In both, `weekStart`
/// is a date that was right a moment ago and is now the wrong answer to the
/// question the screen was asked:
///
///  - **Across a week boundary**, the week that was *this* week is now last
///    week. Holding a date rather than an offset (#117) is what keeps a
///    browsed week still at midnight, and it held the current week still too —
///    the screen went on showing the week just ended, titled "Last Week", with
///    nothing open and the current-week controls gone.
///  - **When the week start changes**, the stored start is a week start in the
///    old calendar and a mid-week day in the new one. Sunday to Monday put the
///    Sunday that opened this week at the *end* of a Monday-first week, so the
///    grid drew last week's seven days; Monday to Sunday left a start that no
///    longer equals the current week's, so New Habit, Blank Row and Edit
///    disappeared from a screen still showing today.
///
/// **The rule is one sentence: the current week follows, any other week stays
/// where it was.** Somebody on the current week was looking at *now*, and now
/// has moved. Somebody paged back was looking at particular days, and those
/// days have not moved — a new week start regroups them, and the week shown is
/// the new-calendar week holding the middle of the old one, which shares at
/// least four of its seven days and is the old week exactly whenever the
/// calendar did not change.
///
/// Pure, per the `WeekGrid` pattern: the caller reads the clock and the
/// preference at the view boundary and hands both down. Clamping into the
/// reach stays the caller's, as it is for every other move (`WeekReach.clamped`).
enum WeekFollow {
    /// The week start to show after today or the week start moved.
    ///
    /// - Parameters:
    ///   - shown: the week start on screen before the change.
    ///   - previousCurrent: the start of the current week before the change,
    ///     in the calendar that was in force then. `shown` equals it exactly
    ///     when the person was on the current week.
    ///   - today: today, after the change.
    ///   - calendar: the calendar after the change, week start included.
    static func weekStart(
        shown: Date,
        previousCurrent: Date,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Date {
        if shown == previousCurrent {
            return WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        }
        // Day arithmetic, then `startOfWeek` normalizes, for the reason
        // `WeekCalendar.startOfWeek` gives: a DST day is 23 or 25 hours long,
        // and a zone that moves its clocks at midnight has days without one.
        let middle = calendar.date(byAdding: .day, value: 3, to: shown) ?? shown
        return WeekCalendar.startOfWeek(containing: middle, calendar: calendar)
    }
}
