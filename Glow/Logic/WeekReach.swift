import Foundation

/// How far back the week view may be paged, as two week starts.
///
/// #116 made any day of the *visible* week editable and left the visible week
/// as one week: the one containing today. This is the other half — which weeks
/// there are to visit — and it is a separate question from `SlotEditing`, which
/// stays a fact about the surface rather than about which week is on screen.
///
/// **The reach is the record's, capped at twelve weeks.** Both halves have a
/// reason:
///
///  - *The record's*, because a week before anything existed holds nothing to
///    correct. A fresh install can page nowhere, which is the truth about it;
///    the reach grows as the app's own history does. `Habit.createdAt` alone
///    would not do — demo history invents completions ten weeks before the
///    habits that carry them — so the record's start is the earlier of the
///    first completion and the first habit.
///  - *Capped*, because the record is not a bound anybody can feel. It also
///    makes the one unusable value harmless: `Habit.createdAt` defaults to
///    `.distantPast` for every row written before it existed, and an
///    uncapped pager over that is a scroll with no end. The cap is what the
///    issue asked for and the record is what makes it meaningful.
///
/// Twelve is a quarter, and comfortably more than the ten weeks
/// `SeededHistory` invents, so the demo's whole past is reachable. Beyond it
/// the surface is History, which is a year of days and does not respond to
/// touch on purpose — see `YearView`.
///
/// **Forward stops at the current week.** There is nothing to correct in a week
/// that has not happened; the days *ahead* are demo-history's, and only within
/// the current week (#116).
///
/// Pure, per the `WeekGrid` pattern: dates in, bounds out, no store and no
/// `Date()`.
struct WeekReach: Equatable, Sendable {
    /// The newest week the view may show: the one containing today.
    let latest: Date
    /// The oldest week the view may show. Never after `latest`.
    let earliest: Date

    /// The furthest back the pager ever goes, whatever the record says.
    static let maximumWeeksBack = 12

    /// The reach for a record that starts at `recordStart`, or no reach at all
    /// when there is no record.
    ///
    /// `recordStart` is the earliest day anything is known about: the first
    /// completion on record, or the first habit's creation, whichever is
    /// earlier. Nil for an empty store.
    static func from(
        recordStart: Date?,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> WeekReach {
        let latest = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        guard let recordStart else { return WeekReach(latest: latest, earliest: latest) }

        let cap = calendar.date(byAdding: .day, value: -7 * maximumWeeksBack, to: latest) ?? latest
        let recorded = WeekCalendar.startOfWeek(containing: recordStart, calendar: calendar)
        // The later of the two floors, and never past the current week: a
        // record that starts in the future — a demo, a sync, a clock that went
        // backwards — leaves the pager exactly where it already is.
        return WeekReach(latest: latest, earliest: min(latest, max(cap, recorded)))
    }

    /// Whether a week starting on `weekStart` is one the view may show.
    func contains(_ weekStart: Date) -> Bool { weekStart >= earliest && weekStart <= latest }

    /// `weekStart` pulled back inside the reach.
    ///
    /// Applied whenever the reach is recomputed, because both ends move: the
    /// latest week moves at midnight, and the earliest moves when the record
    /// does.
    func clamped(_ weekStart: Date) -> Date { min(max(weekStart, earliest), latest) }

    /// `weekStart` moved by `weeks` — negative for earlier — clamped into the
    /// reach.
    ///
    /// Day arithmetic rather than `weekOfYear`, for the reason
    /// `WeekCalendar.week` gives: a DST transition makes one day of the year 23
    /// or 25 hours long, and a week added as anything but whole days can land
    /// on the wrong midnight.
    func step(
        _ weekStart: Date,
        by weeks: Int,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Date {
        let moved = calendar.date(byAdding: .day, value: 7 * weeks, to: weekStart) ?? weekStart
        return clamped(WeekCalendar.startOfWeek(containing: moved, calendar: calendar))
    }
}
