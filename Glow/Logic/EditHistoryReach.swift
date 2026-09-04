import Foundation

/// The weeks Edit History can correct.
///
/// Its past edge is exactly This Week's established record-or-twelve-week
/// floor. Its future edge is different on purpose: twelve weeks after the
/// current week, with no record clause because a future record cannot exist.
struct EditHistoryReach: Equatable, Sendable {
    let earliest: Date
    let latest: Date

    static let futureWeeks = 12

    static func from(
        recordStart: Date?,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> EditHistoryReach {
        let past = WeekReach.from(
            recordStart: recordStart, today: today, calendar: calendar
        )
        let latest = calendar.date(
            byAdding: .day,
            value: 7 * futureWeeks,
            to: past.latest
        ).map {
            WeekCalendar.startOfWeek(containing: $0, calendar: calendar)
        } ?? past.latest
        return EditHistoryReach(earliest: past.earliest, latest: latest)
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
