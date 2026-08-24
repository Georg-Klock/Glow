import Foundation

/// A single Monday-to-Sunday week, as seven midnights.
struct Week: Equatable, Sendable {
    /// Seven days, Monday first, each normalized to midnight in the calendar
    /// that produced them.
    let days: [Date]

    var start: Date { days[0] }

    func contains(_ day: Date) -> Bool { days.contains(day) }

    func index(of day: Date) -> Int? { days.firstIndex(of: day) }

    /// The seven civil days this week is, for a bounded history read (#135).
    /// Everything week-shaped reads only these, so this is all a week's row has
    /// to fetch.
    func dayIDs(in calendar: Calendar = WeekCalendar.calendar) -> ClosedRange<DayID> {
        DayID.range(from: days[0], through: days[6], calendar: calendar)
    }
}

/// Every date question in the app goes through here, so "what day is it" is
/// answered one way rather than five.
///
/// **Including `today()`, which is declared in `Glow/Store/DebugToday.swift`
/// rather than in this file** (#204). Everything here is pure — it takes the
/// dates it is asked about — and `today()` is the one that has to read the
/// clock and the App Group to answer. It is spelled `WeekCalendar.today()` at
/// every call site all the same, so the claim above stays true; only the
/// declaration sits at the boundary, where a store read belongs.
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

    /// The midnight that opens the week `date` falls in.
    ///
    /// **Normalized after the day arithmetic, not only before it** (#242). Day
    /// arithmetic keeps the wall-clock time, and a wall clock that reads
    /// midnight is not always the start of its day: where the DST transition
    /// happens *at* midnight rather than at two or three in the morning — Cuba,
    /// Chile, Brazil until 2019 — a day either has no 00:00 at all or has two
    /// of them, and `date(byAdding:)` resolves that differently from
    /// `startOfDay`. Without the second `startOfDay` this function answered
    /// with two instants an hour apart for the same week, depending on which
    /// day of it was asked about, and every surface here compares weeks by
    /// equality. See `WeekReachTests.theBackChevronAlwaysMoves`.
    static func startOfWeek(containing date: Date, calendar: Calendar = WeekCalendar.calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let moved = calendar.date(byAdding: .day, value: -offset, to: start) else { return start }
        return calendar.startOfDay(for: moved)
    }

    static func week(containing date: Date, calendar: Calendar = WeekCalendar.calendar) -> Week {
        let start = startOfWeek(containing: date, calendar: calendar)
        // Day arithmetic rather than adding 86400 seconds: a DST transition
        // makes one day of the year 23 or 25 hours long, and seconds-based
        // maths lands that week's columns on 23:00 the previous day.
        //
        // Then `startOfDay` over the result, for the reason `startOfWeek`
        // gives: day arithmetic carries the week start's wall clock along, and
        // in a zone that changes its clocks at midnight that wall clock is an
        // hour off this day's own midnight. `Week` promises seven midnights.
        let days = (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return start }
            return calendar.startOfDay(for: day)
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

    /// What to call the week on screen: the days it covers (#190).
    ///
    /// **A week is named by both its ends**, "Aug 17 – 23", because that is the
    /// question a pager leaves you with. This replaces the month name #117 put
    /// in the title, which answered a coarser question — a month holds four or
    /// five of these and every one of them read the same.
    ///
    /// The month is said once when both ends fall in it and twice when they do
    /// not, which is `Date.IntervalFormatStyle`'s own doing rather than this
    /// function's: the collapse, the separator and the order of day and month
    /// are the locale's, so "Aug 31 – Sep 6" is "31. Aug. – 6. Sept." where
    /// that is how a date is written.
    ///
    /// **The year appears only when it is not today's**, which is `monthTitle`'s
    /// rule kept: on the weeks anybody pages to most, a year would be chrome
    /// answering a question nobody has. It used to be argued from the
    /// twelve-week cap — a week reachable from here is at most a quarter back —
    /// and the cap is gone (#186), so the rule stands on its own now and earns
    /// more of its keep than it did: the pager reaches whole years, and those
    /// are exactly the weeks that print one. That rule is not one the interval
    /// style can express — asked for a year it prints both — so a week that
    /// needs one is composed from its two ends instead, and the year is dropped
    /// from the first end when both ends share it: "Dec 29, 2025 – Jan 4",
    /// "Oct 20 – Oct 26, 2025".
    ///
    /// Formatted through the calendar's own locale *and time zone*, not the
    /// process's: a midnight formatted in the wrong zone is the previous day,
    /// and one day in twelve that is the previous month.
    /// What joins the two ends when this function has to compose them.
    ///
    /// An en dash between two thin spaces, which is what
    /// `Date.IntervalFormatStyle` itself produces — measured, not guessed — so
    /// the composed branch and the formatted one do not read as two different
    /// punctuations of the same idea.
    static let rangeSeparator = "\u{2009}\u{2013}\u{2009}"

    static func weekRangeTitle(
        for week: Week,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        let thisYear = calendar.component(.year, from: day(today, calendar: calendar))
        let startYear = calendar.component(.year, from: week.days[0])
        let endYear = calendar.component(.year, from: week.days[6])

        if startYear == thisYear, endYear == thisYear {
            let style = Date.IntervalFormatStyle(
                date: .omitted,
                time: .omitted,
                locale: calendar.locale ?? .current,
                calendar: calendar,
                timeZone: calendar.timeZone
            ).month(.abbreviated).day()
            return (week.days[0]..<week.days[6]).formatted(style)
        }

        func end(_ date: Date, year: Bool) -> String {
            var style = Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: calendar.locale ?? .current,
                calendar: calendar,
                timeZone: calendar.timeZone
            ).month(.abbreviated).day()
            if year { style = style.year() }
            return date.formatted(style)
        }
        // Each end says its own year when that year is not today's, and a year
        // both ends share is said once, at the end: "Oct 20 – Oct 26, 2025"
        // rather than the same four digits twice.
        return end(week.days[0], year: startYear != thisYear && startYear != endYear)
            + Self.rangeSeparator
            + end(week.days[6], year: endYear != thisYear)
    }

    /// How many whole weeks back from `latest` the week starting at
    /// `weekStart` is. Zero on the newest week there is, and never negative:
    /// forward of it there is nothing to count.
    ///
    /// The number, not a phrase. #207's title ladder — *This Week*, *Last
    /// Week*, *Two Weeks Ago*, then a date range — is a switch over this, and
    /// so is `weeksBackTitle` below; both had been counting it themselves.
    ///
    /// **Counted in whole days and divided, rather than in `weekOfYear`.**
    /// #207 proposed `dateComponents([.weekOfYear], ...)` on the grounds that a
    /// *read* between two normalized midnights carries none of the DST hazard
    /// that `WeekReach.step` avoids by adding days. The hazard it does carry is
    /// a different one and is already covered by a test: `weekOfYear` restarts
    /// at 1 January, so twelve weeks back from mid-January reads as −39. See
    /// `WeekCalendarTests.theCountReachesTheFloor`.
    static func weeksBack(
        from weekStart: Date,
        latest: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: day(weekStart, calendar: calendar),
            to: day(latest, calendar: calendar)
        ).day ?? 0
        return max(0, days / 7)
    }

    /// How far back the week on screen is, as a phrase — or nothing at all on
    /// the newest week there is.
    ///
    /// The range title says *which* week; this says *how far*, which is the
    /// half a date range cannot carry on its own. Nil rather than an empty
    /// string, so the caller draws nothing rather than an empty line.
    ///
    /// Only reached from the fourth week back (#207): nearer than that the
    /// title itself is the relative phrase, and a subtitle repeating it would
    /// say the same thing twice.
    static func weeksBackTitle(
        for weekStart: Date,
        latest: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String? {
        let weeks = weeksBack(from: weekStart, latest: latest, calendar: calendar)
        guard weeks > 0 else { return nil }
        return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
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
