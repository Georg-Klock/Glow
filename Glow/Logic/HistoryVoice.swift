import Foundation

/// History, counted and said in one sentence.
///
/// **A week of columns speaks; a month or a year of them counts** (#137). The
/// line is drawn where a person could plausibly want to land on a single day:
/// seven dated marks is a row, and a row is what the app is, so every column of
/// it says its own date and state (`SlotVoice`). Thirty-one of them is a
/// picture of a month and 365 is a picture of a year — swiping through those
/// one cell at a time is not navigation, it is a wall — so those surfaces say
/// what the picture is instead.
///
/// It is the same rule #104 settled for the dots: prefer one element that reads
/// like a sentence over many that read like a table.
///
/// The words are English, as every string in this app is; what is taken from
/// the calendar is the dates and the way a list of clauses is joined, for the
/// reason #104 measured — naming a date by one locale and joining by another
/// produces a sentence in neither.
enum HistoryVoice {
    /// One habit's month, as the month widget's grid actually stands.
    ///
    /// Counted off `MonthGrid`'s own cells rather than off the completions, so
    /// what is spoken is what is drawn: a day the grid Xs is missed here, a day
    /// it leaves blank is still to come, and the rest day — which draws nothing
    /// at all (#72) — is counted as nothing.
    ///
    /// Nil when there are no cells, so a view can drop the value rather than
    /// announce an empty one.
    static func month(
        _ cells: [MonthCell],
        calendar: Calendar = WeekCalendar.calendar
    ) -> String? {
        guard !cells.isEmpty else { return nil }

        let logged = cells.count { $0.mark == .doneToday || $0.mark == .donePast }
        let missed = cells.count { $0.mark == .missed }
        let dueToday = cells.contains { $0.mark == .openToday }
        let upcoming = cells.count { $0.mark == .upcoming }

        var parts: [String] = [
            logged > 0 ? "\(days(logged)) logged this month" : "nothing logged this month"
        ]
        if missed > 0 { parts.append("\(days(missed)) missed") }
        if dueToday { parts.append("due today") }
        if upcoming > 0 { parts.append("\(days(upcoming)) still to come") }
        return sentence(parts, calendar: calendar)
    }

    /// One column of the year grid: which week it is, and how its seven days
    /// went.
    ///
    /// The column is the unit because the column is the drawing — "a vertical
    /// band is a good week", which is what `YearView` is for. Fifty-two stops
    /// is a year a person can swipe through; 365 is not.
    static func week(
        startingOn start: Date,
        fills: [YearHistory.DayFill],
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        let full = fills.count { $0 == .full }
        let partial = fills.count { $0 == .partial }
        let empty = fills.count { $0 == .empty }
        let future = fills.count { $0 == .future }

        var parts: [String] = []
        if full > 0 { parts.append("\(days(full)) complete") }
        if partial > 0 { parts.append("\(days(partial)) partly done") }
        if empty > 0 { parts.append("\(days(empty)) with nothing logged") }
        if future > 0 { parts.append("\(days(future)) still to come") }
        // A week with no days at all cannot happen — the grid builds its
        // columns from seven — but a caller handing over an empty column should
        // get the date rather than a dangling comma.
        guard !parts.isEmpty else { return weekStart(start, calendar: calendar) }
        return "\(weekStart(start, calendar: calendar)), \(sentence(parts, calendar: calendar))"
    }

    /// "Week of 17 August", in the calendar's own locale and time zone. No
    /// weekday: the column *is* the week, and its first day names it.
    static func weekStart(_ start: Date, calendar: Calendar = WeekCalendar.calendar) -> String {
        let style = Date.FormatStyle(
            locale: calendar.locale ?? .current,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .day()
        .month(.wide)
        return "Week of \(start.formatted(style))"
    }

    /// One day, or several.
    private static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    /// The clauses, joined the way the calendar's locale joins a list.
    private static func sentence(_ parts: [String], calendar: Calendar) -> String {
        parts.formatted(.list(type: .and).locale(calendar.locale ?? .current))
    }
}
