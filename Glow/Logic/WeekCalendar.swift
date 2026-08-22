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
    /// The user's own calendar, with the week start taken from settings rather
    /// than from locale.
    ///
    /// Locale would say Sunday in the US. The week start is not a formatting
    /// detail here — it decides which seven days a "week" of habits is, and so
    /// which completions count toward a weekly goal — so it is a setting, and
    /// it defaults to Monday.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = WeekPreferences.firstWeekday
        return calendar
    }

    /// Normalizes an instant to the midnight that owns it — the value every
    /// week-shaped surface compares by equality.
    ///
    /// **A midnight is a position on a timeline, not an identity** (#130). It
    /// is the right thing to draw a week from and the wrong thing to store a
    /// completion as, because the same civil day is a different midnight in
    /// every zone. What a completion records is a `DayID`; this is where one is
    /// placed on the calendar in front of the person looking at it, and
    /// `DayID.date(in:)` produces exactly this value for the same day.
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

    /// What to call the week on screen, now that it is not always this one
    /// (#117).
    ///
    /// **The month you are looking at is the month of the day you are looking
    /// at**, and on a week with no today in it that is where the week begins.
    /// One rule, and it leaves the current week saying exactly what it said
    /// before: a week straddling the end of August still reads "September" on
    /// the 2nd.
    ///
    /// The year appears only when it is not this one, which paging back a
    /// quarter from January reaches. A year on every title would be chrome
    /// answering a question nobody has eleven months of the time.
    ///
    /// Formatted through the calendar's own locale *and time zone*, not the
    /// process's: a midnight formatted in the wrong zone is the previous day,
    /// and one day in twelve that is the previous month.
    static func monthTitle(
        for week: Week,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        let today = day(today, calendar: calendar)
        let anchor = week.contains(today) ? today : week.start
        var style = Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: calendar.locale ?? .current,
            calendar: calendar,
            timeZone: calendar.timeZone
        ).month(.wide)
        if calendar.component(.year, from: anchor) != calendar.component(.year, from: today) {
            style = style.year()
        }
        return anchor.formatted(style)
    }

    /// Single-letter column headers in the user's locale, in the calendar's own
    /// week order.
    static func weekdayInitials(calendar: Calendar = WeekCalendar.calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        // veryShortStandaloneWeekdaySymbols is Sunday-first regardless of
        // firstWeekday, so rotate it into the calendar's own order.
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}
