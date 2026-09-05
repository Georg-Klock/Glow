import Foundation

/// Which of This Week's three modes is on screen (#557).
///
/// **One view, genuinely mode-switched — not two views cooperating.** Browsing
/// draws the cadence's marks and offers today's action; editing the list fans
/// the rows open for reorder and delete; correcting history swaps every row's
/// track for seven plain circles, one per civil day, and is the one surface
/// that writes an arbitrary day (#543). Correct History was a separate
/// full-screen `EditHistoryView` until #557 — its own `List`, toolbar and
/// pager, sliding up over This Week. What it needed from that screen was its
/// reach and its write rule; both are decisions rather than chrome, so they
/// are here and in `HabitStore`, and the screen is gone.
///
/// Pure, per the `WeekGrid` pattern: the mode is a value, the rules below take
/// dates in and hand bounds out, and nothing here reads a store or the clock.
enum WeekGridMode: Equatable, Sendable {
    case browsing
    case editingList
    case correctingHistory

    /// The weeks the pager may visit in this mode.
    ///
    /// Browsing stops at the current week: a forward chevron there would be a
    /// control that can never do anything (#207). Correcting reaches exactly
    /// twelve weeks past it (#543), because a day ahead can be corrected too.
    /// The list is only editable on the current week, so its reach is
    /// browsing's — `WeeklyGridView.show(week:)` ends that mode on the way to
    /// any other week.
    ///
    /// One pager, two reaches (#557): the same chevrons consult whichever of
    /// these the mode names, rather than always asking `WeekReach`.
    func reach(
        recordStart: Date?,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> any WeekBounds {
        switch self {
        case .browsing, .editingList:
            WeekReach.from(recordStart: recordStart, today: today, calendar: calendar)
        case .correctingHistory:
            EditHistoryReach.from(recordStart: recordStart, today: today, calendar: calendar)
        }
    }

    /// Whether the list's own management is on offer: swipe actions, the
    /// remove and reorder controls, the ••• menu and the label's tap into a
    /// habit's editor.
    ///
    /// Correcting asks one question per day — did this happen — and nothing
    /// about the list, which is what the separate screen already excluded and
    /// what carries over unchanged (#557).
    var offersHabitManagement: Bool { self != .correctingHistory }

    /// Whether a day's mark is drawn as a fact rather than as a judgement: a
    /// plain filled or empty circle instead of the cadence's open, missed,
    /// rest and joined marks (#543).
    var drawsFactualDays: Bool { self == .correctingHistory }
}

/// What the week pager needs of a reach: its two week starts, and the
/// arithmetic between them.
///
/// `WeekReach` and `EditHistoryReach` both already answer these; the protocol
/// is what lets one pager hold either (#557). Both bounds are week starts —
/// see `WeekReach.from` for why that normalisation is load-bearing.
protocol WeekBounds: Sendable {
    /// The oldest week the pager may show.
    var earliest: Date { get }
    /// The newest week the pager may show.
    var latest: Date { get }
    func contains(_ weekStart: Date) -> Bool
    func clamped(_ weekStart: Date) -> Date
    func step(_ weekStart: Date, by weeks: Int, calendar: Calendar) -> Date
}

extension WeekBounds {
    /// `step` in the app's own calendar; a protocol requirement cannot carry
    /// the default the concrete types give it.
    func step(_ weekStart: Date, by weeks: Int) -> Date {
        step(weekStart, by: weeks, calendar: WeekCalendar.calendar)
    }
}

extension WeekReach: WeekBounds {}
extension EditHistoryReach: WeekBounds {}

/// What a week is called relative to the current one, in both directions.
///
/// #207 built the ladder for weeks behind — a relative phrase for the three
/// anybody names that way, the dates beyond them, the distance underneath.
/// Correcting history pages ahead as well (#543, #557), so the ladder needs
/// its mirror: the same three rungs forward, then the dates with "N weeks
/// ahead" under them. Nothing forward is reached while browsing, so the
/// browsing titles are exactly what they were.
enum WeekDistanceTitle {
    /// The signed distance from the current week to `weekStart`, in whole
    /// weeks: negative behind, positive ahead, zero for the current week.
    ///
    /// `WeekCalendar.weeksBack` floors at zero, which was right while nothing
    /// forward existed and is wrong the moment it does — a week ahead read as
    /// "This Week".
    static func weeks(
        from current: Date,
        to weekStart: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: WeekCalendar.day(current, calendar: calendar),
            to: WeekCalendar.day(weekStart, calendar: calendar)
        ).day ?? 0
        // Toward zero either way, so a DST-shortened week still counts as one.
        return days / 7
    }

    /// The title line: the relative phrase where one exists, else `range`.
    static func title(weeks: Int, range: String) -> String {
        switch weeks {
        case 0: "This Week"
        case -1: "Last Week"
        case -2: "Two Weeks Ago"
        case 1: "Next Week"
        case 2: "Two Weeks Ahead"
        default: range
        }
    }

    /// The line under the title: the dates when the title is a phrase, the
    /// distance when the title is the dates, nothing on the current week.
    static func subtitle(weeks: Int, range: String) -> String? {
        switch weeks {
        case 0: nil
        case -2, -1, 1, 2: range
        case ..<0: -weeks == 1 ? "1 week ago" : "\(-weeks) weeks ago"
        default: weeks == 1 ? "1 week ahead" : "\(weeks) weeks ahead"
        }
    }
}
