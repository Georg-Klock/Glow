import Foundation

/// Which days a surface lets a tap touch.
///
/// The app and the widget share `WeekGrid` and `WeekSpans` deliberately, so
/// that what a slot draws and what it does are decided in one place. Since #116
/// the two surfaces want different answers — the week view edits any day of the
/// week it shows, the widget edits today — so the difference is *declared* here
/// rather than forked into two grids that would drift.
///
/// **No default value anywhere this is passed.** A new call site has to say
/// which surface it is; a default would let one inherit the permissive answer by
/// forgetting to think about it.
///
/// The rest day is not one of the cases. It is refused on every surface, and it
/// is refused by `HabitStore` as well as here — a widget renders in a second
/// process and can hold a surface built before the setting changed, so the rule
/// cannot live in "no button was offered".
enum SlotEditing: Equatable, Sendable {
    /// The widget, its intents, and the month grid: today and nothing else.
    case todayOnly
    /// The week view. `allowingFuture` opens the days after today, which only
    /// demo history does — outside it you can correct the past, not claim the
    /// future, because a completion logged ahead is a claim about something
    /// that has not happened.
    ///
    /// The case is about the *surface*, not about which week is on screen: a
    /// week view showing an earlier week asks the same question of each of its
    /// days, which is what #117 widens without unpicking anything here.
    case week(allowingFuture: Bool)

    /// Whether a tap may land on `day` at all, before the rest day is asked.
    ///
    /// Both dates are midnights — `WeekCalendar.day` — so this compares days
    /// rather than instants.
    func allows(_ day: Date, today: Date) -> Bool {
        switch self {
        case .todayOnly: day == today
        case .week(let allowingFuture): allowingFuture || day <= today
        }
    }

    /// The day a tap on `column` writes, or nil when that column takes no
    /// write.
    ///
    /// **This is the one place "which slot is actionable" is decided.**
    /// `WeekGrid` asks it per column, `WeekSpans` asks it for every column a
    /// span covers, and the week view asks it again for the column under a
    /// finger. Three questions, one answer, so a row cannot draw a tap target
    /// it will not honour.
    func day(
        atColumn column: Int,
        in week: Week,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Date? {
        guard week.days.indices.contains(column) else { return nil }
        let day = week.days[column]
        guard !WeekPreferences.isRestDay(day, calendar: calendar) else { return nil }
        guard allows(day, today: WeekCalendar.day(today, calendar: calendar)) else { return nil }
        return day
    }
}
