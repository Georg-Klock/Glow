import Foundation

/// Which day the week starts on, and which day — if any — is a rest day.
///
/// In the App Group, because the widget draws the same seven columns and a
/// widget whose week started on a different day from the app would be a bug
/// nobody could explain.
///
/// **The rest day is retired for MVP scope** (#390). Nothing in Settings offers
/// it, `retireRestDay()` clears what an older build stored, and the arithmetic
/// below is left inert rather than swept out — see #391 and #392. What follows
/// describes how it works if it comes back, and how the tests still reach it.
///
/// **This is where the stored rest day lives, and the only place it is read**
/// (#181). Every surface reads it once — a view through `@AppStorage`, a widget
/// once per render, `HabitStore` once per instance — and hands the value down
/// as a parameter, exactly as the calendar arrives. Nothing in `Glow/Logic/`
/// reaches back here for it, which is what `TestRunnerContractTests` scans for.
///
/// It was the one thing that broke the rule that decision logic takes no store,
/// and four issues in one night were spent making that harmless in one more
/// situation each: #105, #168, #175, #179.
enum WeekPreferences {
    static let firstWeekdayKey = "weekFirstWeekday"
    static let restDayKey = "weekRestDay"

    /// `Calendar`'s own numbering: 1 is Sunday through 7 is Saturday. Kept in
    /// those terms rather than an enum of our own so it can be handed to
    /// `Calendar.firstWeekday` without a translation step that could invert.
    static let sunday = 1
    static let monday = 2

    /// Monday, not the locale's answer.
    ///
    /// Locale would say Sunday in the US, and the week start is not a formatting
    /// detail here — it decides which seven days a "week" of habits is, and so
    /// which completions count toward a weekly goal.
    static let defaultFirstWeekday = monday

    private static var store: UserDefaults { GlowSettings.store }

    static var firstWeekday: Int {
        get {
            let stored = store.object(forKey: firstWeekdayKey) as? Int
            return clampWeekday(stored ?? defaultFirstWeekday)
        }
        set { store.set(clampWeekday(newValue), forKey: firstWeekdayKey) }
    }

    /// The day of the week nothing is expected on, or nil for none.
    ///
    /// **Nothing in the app can set this any more** (#390). The Settings rows
    /// that offered it — a toggle and a day picker — are gone for MVP scope,
    /// and `retireRestDay()` clears whatever an earlier build left stored, so
    /// on a real install this reads nil and keeps reading nil. The accessor
    /// stays because the arithmetic underneath it stays: `RestCut`,
    /// `RestWindow`, `WeekSpans`' `isRestDay` checks and their tests are inert
    /// rather than deleted, and this is how the tests reach them. See #391 and
    /// #392, which are where the feature comes back.
    ///
    /// **Read at a boundary, then passed down.** A view reads it through
    /// `@AppStorage` so SwiftUI can see the dependency, the widget reads it once
    /// per render, and `HabitStore` takes it as an initializer argument the way
    /// it takes a calendar. See `restDay(stored:)`.
    static var restDay: Int? {
        get { restDay(stored: store.object(forKey: restDayKey) as? Int ?? 0) }
        set { store.set(newValue.map(clampWeekday) ?? 0, forKey: restDayKey) }
    }

    /// Clears the stored rest day, so an install that had one before #390 stops
    /// having one.
    ///
    /// Called once per launch from `GlowApp.init`, beside
    /// `DebugToday.clearOnLaunch()` and for the same shape of reason: a value
    /// no surface can change any more must not go on being read. Unconditional
    /// rather than guarded by a "has migrated" flag — removing an absent key is
    /// a no-op, and a flag would be a second thing to be wrong.
    ///
    /// **The widget is one refresh behind, and only once.** It reads the same
    /// App Group, so between installing a build with this in it and launching
    /// the app for the first time, a placed widget can still draw the old rest
    /// column. The launch that clears the key is followed by
    /// `WidgetRefresh.invalidate()` in `GlowApp`'s `body`, which closes it.
    static func retireRestDay() {
        store.removeObject(forKey: restDayKey)
    }

    /// The stored integer as a rest day: 0 is none, anything else is a weekday.
    ///
    /// The conversion lives here rather than at each `@AppStorage` — the raw
    /// value is what a view can observe, and the meaning of that raw value is
    /// this type's. Clamped for the reason `clampWeekday` gives.
    static func restDay(stored: Int) -> Int? {
        stored == 0 ? nil : clampWeekday(stored)
    }

    /// Out-of-range values could arrive from a synced default or a future
    /// build, and `Calendar.firstWeekday = 9` silently produces a week that
    /// starts on the wrong day rather than throwing.
    static func clampWeekday(_ value: Int) -> Int {
        min(max(value, 1), 7)
    }

    /// The weekday numbers in display order, given a week start.
    ///
    /// Sunday-first is the order the picker offers, because that is how the
    /// symbols come out of `Calendar` and how a day list reads to most people.
    static let pickerOrder = Array(1...7)

    /// Whether a date falls on the rest day.
    ///
    /// **The rest day is the argument, not a lookup** (#181). This used to read
    /// the stored value itself, which put a process-wide store inside every
    /// grid, span and month that asked. It takes the answer now, so a caller
    /// that has not decided cannot silently inherit one.
    static func isRestDay(
        _ date: Date, restDay: Int?, calendar: Calendar = WeekCalendar.calendar
    ) -> Bool {
        guard let restDay else { return false }
        return calendar.component(.weekday, from: date) == clampWeekday(restDay)
    }
}
