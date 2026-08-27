import Foundation

/// History, counted and said in one sentence.
///
/// **A week of columns speaks; a month of them counts** (#137). The line is
/// drawn where a person could plausibly want to land on a single day: seven
/// dated marks is a row, and a row is what the app is, so every column of it
/// says its own date and state (`SlotVoice`). Thirty-one of them is a picture
/// of a month — swiping through it one cell at a time is not navigation, it is
/// a wall — so that surface says what the picture is instead. (The year grid
/// was the other counted surface until #316 removed it.)
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

    /// One day, or several.
    private static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    /// The clauses, joined the way the calendar's locale joins a list.
    private static func sentence(_ parts: [String], calendar: Calendar) -> String {
        parts.formatted(.list(type: .and).locale(calendar.locale ?? .current))
    }
}
