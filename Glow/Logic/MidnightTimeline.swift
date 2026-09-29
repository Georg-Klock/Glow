import Foundation

/// The days a widget timeline carries an entry for: today, and the next local
/// midnight (#345).
///
/// **A reload policy is a request; an entry is a guarantee.** Every widget
/// timeline asks to be rebuilt `.after(midnight)`, but WidgetKit decides when
/// it obliges, and until it does the Home Screen keeps rendering the last
/// entry it was given. An entry that still says today is yesterday draws
/// yesterday's open mark lit on a day it is no longer actionable — the one
/// thing SPEC §1 says light must never do — and a tap on it is refused as
/// stale, so the mark flips and flips back. A second entry dated at midnight
/// costs nothing and needs no reload to be right.
///
/// Pure: "today" arrives as a parameter and the store read as a closure, so
/// the decision is testable without a provider, a store or a clock.
enum MidnightTimeline {
    /// The start of the day after `date`'s, in `calendar` — the next local
    /// midnight. Nil only if the calendar cannot add a day.
    static func next(
        after date: Date, calendar: Calendar = WeekCalendar.calendar
    ) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: WeekCalendar.day(date, calendar: calendar))
    }

    /// The small family's days: `today`, then the next midnight, each with the
    /// month it is drawn from.
    ///
    /// The record does not change at midnight; *today* does, and `MonthGrid`
    /// is a function of both. So the midnight entry reuses today's read when
    /// midnight falls in the same drawn range (`MonthGrid.dayRange`), and
    /// reads again when it does not — on the 1st the widget draws a different
    /// month, whose whole weeks reach days the old read never asked for.
    /// Reusing the old month there would keep drawing the month that ended.
    static func monthDays<Month>(
        today: Date,
        calendar: Calendar = WeekCalendar.calendar,
        read: (Date) -> Month
    ) -> [(day: Date, month: Month)] {
        let month = read(today)
        guard let midnight = next(after: today, calendar: calendar) else {
            return [(today, month)]
        }
        let sameRange = MonthGrid.dayRange(containing: today, calendar: calendar)
            == MonthGrid.dayRange(containing: midnight, calendar: calendar)
        return [(today, month), (midnight, sameRange ? month : read(midnight))]
    }
}
