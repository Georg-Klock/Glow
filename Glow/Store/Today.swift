import Foundation

/// Where "today" is decided, once.
///
/// **Declared here, in `Glow/Store/`, rather than in `Glow/Logic/`.** Decision
/// logic is pure — no views, no store, no `Date()` — and this function reads the
/// clock. Putting it in `WeekCalendar.swift` would make that file the first in
/// `Glow/Logic/` to do so, which is the rule #181 spent four issues restoring.
/// The spelling stays `WeekCalendar.today()` because the call sites read best
/// that way and because `WeekCalendar`'s own header claims to be where "what
/// day is it" is answered — it is; the answer simply arrives from the boundary.
/// See `TestIsolationTests.logicDoesNotReadTheClock`, which is what stops this
/// extension being reached from inside `Glow/Logic/`.
///
/// It used to consult a debug override in the App Group first (#204). That
/// tool is gone (#628), so today is the clock's today and nothing else.
extension WeekCalendar {
    /// Today, as a midnight in `calendar`.
    ///
    /// Every surface that establishes "today" calls this and hands the answer
    /// down as a parameter, exactly as `calendar:` and `restDay:` are handed
    /// down.
    static func today(calendar: Calendar = WeekCalendar.calendar) -> Date {
        day(Date(), calendar: calendar)
    }
}
