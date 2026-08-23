import Foundation

/// Which day of *this* week the app is pretending it is, or nothing at all.
///
/// A debug tool with real write powers (#204). While an override is set every
/// screen, every edit rule and every widget treats the chosen day as today, and
/// a tap logs a genuine completion dated to it. It is a simulation, not a
/// preview — which is why it is fenced in three ways rather than one:
///
///  1. **Scoped to the current week.** Once the real day rolls into a different
///     week than the one the override was set within, an override for
///     "Wednesday" stops meaning anything, and silently keeping it would mean a
///     debug tool nobody remembers is on quietly rewriting what today is,
///     indefinitely. `override(calendar:)` clears it on the way out.
///  2. **Cleared at launch.** `GlowApp.init` calls `clearOnLaunch()`, so the
///     longest a stray override can affect anything is one app session. See
///     that call site for why this is not merely tidiness.
///  3. **Said out loud.** `DebugTodayBanner` sits on every screen that reads
///     it. A forgotten override does not just mis-render, it mis-*writes*, and
///     once written a simulated completion is indistinguishable from a real
///     one.
///
/// In the App Group, beside `WeekPreferences` and for the same reason: the
/// widget draws the same week from its own process, so the override reaches it
/// without any plumbing of its own.
///
/// **This ships in every build, including TestFlight** — the same tier as demo
/// history, not `#if DEBUG`. A `#if DEBUG` version would compile out of every
/// Release archive, including the one installed on a phone through TestFlight,
/// which is where this app is actually tested day to day.
enum DebugToday {
    static let key = "debugTodayOverride"

    private static var store: UserDefaults { GlowSettings.store }

    /// The overridden day, or nil when it is off or has gone stale.
    ///
    /// Stale means "not in this week", and the comparison is against the seven
    /// midnights `WeekCalendar` would produce right now. A stored midnight from
    /// another time zone — or from a week start the user has since changed —
    /// matches none of them and is therefore treated as stale, which is the
    /// safe direction for a value that decides what a tap writes.
    static func override(calendar: Calendar = WeekCalendar.calendar) -> Date? {
        guard let stored = store.object(forKey: key) as? Date else { return nil }
        let real = WeekCalendar.day(Date(), calendar: calendar)
        let realWeek = WeekCalendar.week(containing: real, calendar: calendar)
        guard realWeek.contains(stored) else {
            store.removeObject(forKey: key)
            return nil
        }
        return stored
    }

    /// Whether an override is currently in force. The banner's question.
    static func isActive(calendar: Calendar = WeekCalendar.calendar) -> Bool {
        override(calendar: calendar) != nil
    }

    /// Sets the override to a day, or clears it with nil.
    ///
    /// The day is normalized on the way in, so a picker handing over any
    /// instant of the day stores the midnight the week is made of — the value
    /// `override` compares by equality.
    static func set(_ day: Date?, calendar: Calendar = WeekCalendar.calendar) {
        if let day {
            store.set(WeekCalendar.day(day, calendar: calendar), forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    /// The seven days the override may be set to: the *real* current week.
    ///
    /// The real one, not the overridden one, which is what keeps the picker a
    /// closed loop — an override can always be moved to any other day of the
    /// week it was set within, and can never walk itself into a different week
    /// one day at a time.
    static func choices(calendar: Calendar = WeekCalendar.calendar) -> [Date] {
        WeekCalendar.week(
            containing: WeekCalendar.realToday(calendar: calendar), calendar: calendar
        ).days
    }

    /// A day as its weekday name.
    ///
    /// Formatted through the calendar's own locale *and* time zone rather than
    /// the process's, for `weekRangeTitle`'s reason: a midnight formatted in
    /// the wrong zone is the previous day, and this string is the whole of what
    /// the banner claims.
    static func dayName(_ day: Date, calendar: Calendar = WeekCalendar.calendar) -> String {
        let style = Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: calendar.locale ?? .current,
            calendar: calendar,
            timeZone: calendar.timeZone
        ).weekday(.wide)
        return day.formatted(style)
    }

    /// Forgets any override, unconditionally.
    ///
    /// Named rather than spelled `set(nil)` at the call site because what it is
    /// for is the point: an override must not outlive the session that set it.
    static func clearOnLaunch() {
        store.removeObject(forKey: key)
    }
}

/// Where "today" is decided, once.
///
/// **Declared here, in `Glow/Store/`, rather than in `Glow/Logic/`.** Decision
/// logic is pure — no views, no store, no `Date()` — and this function is both
/// of the last two: it reads the clock and it reads the App Group. Putting it
/// in `WeekCalendar.swift` would have made that file the first in `Glow/Logic/`
/// to do either, which is the rule #181 spent four issues restoring. The
/// spelling stays `WeekCalendar.today()` because the call sites read best that
/// way and because `WeekCalendar`'s own header claims to be where "what day is
/// it" is answered — it is; the answer simply arrives from the boundary. See
/// `TestIsolationTests.logicDoesNotReadTheClock`, which is what stops this
/// extension being reached from inside `Glow/Logic/`.
extension WeekCalendar {
    /// Today, as the app is currently willing to believe it.
    ///
    /// Every surface that establishes "today" calls this and hands the answer
    /// down as a parameter, exactly as `calendar:` and `restDay:` are handed
    /// down. Nothing downstream — `WeekGrid`, `WeekSpans`, `SlotEditing`'s
    /// future-write guard, the widget's providers — knows an override exists.
    static func today(calendar: Calendar = WeekCalendar.calendar) -> Date {
        DebugToday.override(calendar: calendar) ?? day(Date(), calendar: calendar)
    }

    /// The real day, whatever the override says. For the half of the banner
    /// that says what today actually is, and for nothing else.
    static func realToday(calendar: Calendar = WeekCalendar.calendar) -> Date {
        day(Date(), calendar: calendar)
    }
}
