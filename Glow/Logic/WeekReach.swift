import Foundation

/// How far back the week view may be paged, as two week starts.
///
/// #116 made any day of the *visible* week editable and left the visible week
/// as one week: the one containing today. This is the other half — which weeks
/// there are to visit — and it is a separate question from `SlotEditing`, which
/// stays a fact about the surface rather than about which week is on screen.
///
/// **The reach is the record's, and that is the whole rule** (#186). A week
/// before anything existed holds nothing to correct, so a fresh install can
/// page nowhere, which is the truth about it; the reach grows as the app's own
/// history does. `Habit.createdAt` alone would not do — demo history invents
/// completions ten weeks before the habits that carry them — so the record's
/// start is the earlier of the first completion and the first habit, taken by
/// `HabitStore.earliestRecordedDay`.
///
/// **It was capped at twelve weeks until #186, and the argument for the cap is
/// kept rather than deleted**, because it had two halves and they are not the
/// same kind of claim.
///
///  - *The record is not a bound anybody can feel.* Twelve weeks is a quarter,
///    comfortably more than the ten weeks `SeededHistory` invents, and a
///    tracker that lets you edit a quarter of a year may be a tracker whose
///    record cannot be trusted. That was a real argument about how much rope a
///    person gets, and it was **overruled deliberately**: the pager pages back,
///    and edits, as far as the record genuinely reaches. Splitting it — looking
///    further than you may edit — was considered and refused; one bound, not
///    two. The costs are storage and drawing, and neither justifies a cap:
///    the history is SQLite, the grid draws one week at a time, and eight
///    habits over ten years is about 29,000 rows. Measured, not assumed —
///    `HistoryProjectionTests.aDeepWeekCostsWhatAWeekCosts`.
///  - *`.distantPast` makes "as far as the record reaches" unbounded.*
///    `Habit.createdAt` defaults to it for every row written before that column
///    existed, and an uncapped pager over a record that starts in the year 1 is
///    a scroll with no end. That half was simply true — and it is **fixed at
///    its source instead of survived here**: a default creation date means
///    *unknown*, not *the year 1*, and `HabitStore.earliestRecordedDay` no
///    longer lets one start the record. See `Habit.hasKnownCreation`.
///
/// So one half was a judgement and was overruled, and the other was a hazard
/// and was repaired. Neither is a reason to bound the pager, and nothing here
/// bounds it under a second name.
///
/// **`recordStart` is trusted, and that is where the hazard now lives.** This
/// type takes the date it is given; a caller that hands it a sentinel gets a
/// reach back to the sentinel. The one guard is in `earliestRecordedDay`,
/// which is where the tables are read — see `WeekReachTests.theSentinelIsNotThisTypesToRefuse`.
///
/// **Forward stops at the current week.** There is nothing to correct in a week
/// that has not happened; the days *ahead* are demo-history's, and only within
/// the current week (#116). History — a year of days, and deliberately not
/// touchable — is a different view of the same record rather than what happens
/// past the end of this one.
///
/// Pure, per the `WeekGrid` pattern: dates in, bounds out, no store and no
/// `Date()`.
struct WeekReach: Equatable, Sendable {
    /// The newest week the view may show: the one containing today.
    let latest: Date
    /// The oldest week the view may show. Never after `latest`.
    let earliest: Date

    /// The reach for a record that starts at `recordStart`, or no reach at all
    /// when there is no record.
    ///
    /// `recordStart` is the earliest day anything is known about: the first
    /// completion on record, or the first habit's creation where that is a date
    /// rather than the unknown-creation sentinel, whichever is earlier. Nil for
    /// an empty store, and for one that holds nothing but sentinels.
    static func from(
        recordStart: Date?,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> WeekReach {
        let latest = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        guard let recordStart else { return WeekReach(latest: latest, earliest: latest) }

        // **Both floors are week starts, and normalizing this one is
        // load-bearing** (#242). An `earliest` that is not a week start is
        // compared against week starts by `contains`, `clamped` and the pager's
        // own `.disabled`, and in a zone that changes its clocks at midnight the
        // two can name the same week an hour apart — which draws a back chevron
        // that is lit and does nothing. The twelve-week cap this used to take a
        // `max` against was normalized for exactly that reason; the cap is gone
        // and the normalization is not.
        let recorded = WeekCalendar.startOfWeek(containing: recordStart, calendar: calendar)
        // Never past the current week: a record that starts in the future — a
        // demo, a sync, a clock that went backwards — leaves the pager exactly
        // where it already is.
        return WeekReach(latest: latest, earliest: min(latest, recorded))
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
