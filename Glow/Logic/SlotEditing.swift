import Foundation

/// Which days a surface lets a tap touch.
///
/// The app and the widget share `WeekGrid` and `WeekSpans` deliberately, so
/// that what a slot draws and what it does are decided in one place. Since #543
/// every cadence-shaped surface has the same answer: today only. Past and
/// future corrections live in This Week's correcting mode (#557), whose plain
/// factual circles intentionally do not use either cadence grid.
///
/// **No default value anywhere this is passed.** A new call site has to say
/// which surface it is; a default would let one inherit the permissive answer by
/// forgetting to think about it.
///
/// The rest day is not one of the cases. It is refused on every surface, and it
/// is refused by `HabitStore` as well as here — a widget renders in a second
/// process and can hold a surface built before the setting changed, so the rule
/// cannot live in "no button was offered".
///
/// It arrives beside this, as a parameter, for the same reason this one does
/// (#181): a surface says which days it edits *and* which day it rests, and
/// neither is read out of a store from in here.
enum SlotEditing: Equatable, Sendable {
    /// This Week and every app- or Home-Screen-hosted widget: today and
    /// nothing else. This supersedes #116/#117 and #508/#526's wider scopes.
    case todayOnly

    /// Whether a tap may land on `day` at all, before the rest day is asked.
    ///
    /// Both dates are midnights — `WeekCalendar.day` — so this compares days
    /// rather than instants.
    func allows(_ day: Date, today: Date) -> Bool {
        day == today
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
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Date? {
        guard week.days.indices.contains(column) else { return nil }
        let day = week.days[column]
        guard !WeekPreferences.isRestDay(day, restDay: restDay, calendar: calendar) else {
            return nil
        }
        guard allows(day, today: WeekCalendar.day(today, calendar: calendar)) else { return nil }
        return day
    }
}

/// Whether a surface still offers today once the week's goal is met (#560).
///
/// `SlotEditing` says which *days* a tap may touch, and every cadence surface
/// answers "today". This is the second question a met row raises: today is not
/// owed any more, so does the row still take a rep? The two surfaces answer
/// differently, and for a reason that belongs to the surface rather than to
/// the arithmetic — which is why it arrives as a parameter, with no default a
/// new caller could inherit, exactly as `SlotEditing` does.
///
/// A completion logged this way is a bonus mark like any other (#543): same
/// fill, same words, no third tier. What this decides is only whether the tap
/// that makes one is offered.
enum BonusEditing: Equatable, Sendable {
    /// This Week: today's column of a filled row takes one more completion,
    /// which becomes its own mark, and that mark's tap takes it back again.
    /// `SpanView` resolves the column under the finger, so today's part of a
    /// bar can mean today while the bar keeps saying when the goal was met.
    case today

    /// Home-Screen and in-app widgets, and every history projection: a met row
    /// offers nothing. WidgetKit reports no touch location inside one custom
    /// control, so a filled multi-day bar cannot tell today's column from
    /// Monday's — one `Toggle` across the bar would offer Monday's pixels as
    /// today's rep. The widget keeps the marks it draws and no more (#560).
    case never
}
