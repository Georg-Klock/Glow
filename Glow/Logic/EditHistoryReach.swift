import Foundation

/// The weeks Correct History can reach: a flat four weeks behind the current
/// week and four ahead of it (#592, narrowing #543).
///
/// **Both edges are numbers now, and the record does not move either.** #543
/// gave the mode This Week's past edge — `WeekReach`'s record-or-twelve-week
/// floor, which the record extends indefinitely — and a flat twelve weeks
/// ahead. #592 took the Today button out of the mode's bar, and a reach a
/// person has to step through one week at a time has to be short enough to
/// step: four weeks each way is a handful of taps in the worst case where
/// twelve, or an unbounded record, was not. The cost is named in
/// `docs/decisions.md`: a completion older than four weeks is no longer
/// correctable through this screen.
///
/// So this type no longer reuses `WeekReach` at all. That reach is unbounded
/// upward by design — the record extends the floor and never shortens it —
/// and this one deliberately is not; sharing the past edge would reintroduce
/// the reach it exists to bound. Both edges are week starts, for the reason
/// `WeekReach.from` gives (#242).
///
/// Pure, per the `WeekGrid` pattern: a date in, two week starts out, no store
/// and no `Date()`.
struct EditHistoryReach: Equatable, Sendable {
    let earliest: Date
    let latest: Date

    /// Weeks behind the current week the mode reaches.
    static let pastWeeks = 4
    /// Weeks ahead of the current week the mode reaches.
    static let futureWeeks = 4

    static func from(
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> EditHistoryReach {
        let current = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        // Day arithmetic rather than `weekOfYear`, for the reason `step`
        // gives: a DST transition makes one day 23 or 25 hours long, and a
        // span added as anything but whole days can land on the wrong midnight.
        let earliest = calendar.date(
            byAdding: .day, value: -7 * pastWeeks, to: current
        ).map {
            WeekCalendar.startOfWeek(containing: $0, calendar: calendar)
        } ?? current
        let latest = calendar.date(
            byAdding: .day, value: 7 * futureWeeks, to: current
        ).map {
            WeekCalendar.startOfWeek(containing: $0, calendar: calendar)
        } ?? current
        return EditHistoryReach(earliest: earliest, latest: latest)
    }

    func contains(_ weekStart: Date) -> Bool {
        weekStart >= earliest && weekStart <= latest
    }

    func clamped(_ weekStart: Date) -> Date {
        min(max(weekStart, earliest), latest)
    }

    func step(
        _ weekStart: Date,
        by weeks: Int,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Date {
        let moved = calendar.date(
            byAdding: .day, value: 7 * weeks, to: weekStart
        ) ?? weekStart
        return clamped(
            WeekCalendar.startOfWeek(containing: moved, calendar: calendar)
        )
    }
}
