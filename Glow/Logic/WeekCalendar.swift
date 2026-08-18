import Foundation

/// A single Monday-to-Sunday week, as seven midnights.
struct Week: Equatable, Sendable {
    /// Seven days, Monday first, each normalized to midnight in the calendar
    /// that produced them.
    let days: [Date]

    var start: Date { days[0] }

    func contains(_ day: Date) -> Bool { days.contains(day) }

    func index(of day: Date) -> Int? { days.firstIndex(of: day) }
}

/// Every date question in the app goes through here, so "what day is it" is
/// answered one way rather than five.
enum WeekCalendar {
    /// The user's own calendar, forced to a Monday week start to match the
    /// M T W T F S S header. Locale decides the week start otherwise, and in
    /// the US that is Sunday, which would silently shift every column.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Normalizes an instant to the midnight that owns it. `Completion.day` is
    /// always this, never a timestamp, so completions compare by equality.
    static func day(_ date: Date, calendar: Calendar = WeekCalendar.calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfWeek(containing date: Date, calendar: Calendar = WeekCalendar.calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    static func week(containing date: Date, calendar: Calendar = WeekCalendar.calendar) -> Week {
        let start = startOfWeek(containing: date, calendar: calendar)
        // Day arithmetic rather than adding 86400 seconds: a DST transition
        // makes one day of the year 23 or 25 hours long, and seconds-based
        // maths lands that week's columns on 23:00 the previous day.
        let days = (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: start) ?? start
        }
        return Week(days: days)
    }

    /// Day-of-month numbers for a week's columns, as displayed strings.
    ///
    /// Formatted through the calendar rather than by interpolating the integer,
    /// so a non-Gregorian or non-Latin locale shows its own numerals.
    static func dayNumbers(in week: Week, calendar: Calendar = WeekCalendar.calendar) -> [String] {
        let formatter = NumberFormatter()
        formatter.locale = calendar.locale ?? .current
        return week.days.map { day in
            let number = calendar.component(.day, from: day)
            return formatter.string(from: NSNumber(value: number)) ?? String(number)
        }
    }

    /// Single-letter column headers in the user's locale, Monday first.
    static func weekdayInitials(calendar: Calendar = WeekCalendar.calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        // veryShortStandaloneWeekdaySymbols is Sunday-first regardless of
        // firstWeekday, so rotate it into the calendar's own order.
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}
