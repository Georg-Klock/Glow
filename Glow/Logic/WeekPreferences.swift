import Foundation

/// Which day the week starts on, and which day — if any — is a rest day.
///
/// In the App Group, because the widget draws the same seven columns and a
/// widget whose week started on a different day from the app would be a bug
/// nobody could explain.
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

    /// The day of the week nothing is expected on, or nil for none — which is
    /// the default, because a tracker that assumes you rest on Sunday is wrong
    /// about most people.
    static var restDay: Int? {
        get {
            guard let stored = store.object(forKey: restDayKey) as? Int else { return nil }
            return stored == 0 ? nil : clampWeekday(stored)
        }
        set { store.set(newValue.map(clampWeekday) ?? 0, forKey: restDayKey) }
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
    static func isRestDay(_ date: Date, calendar: Calendar = WeekCalendar.calendar) -> Bool {
        guard let restDay else { return false }
        return calendar.component(.weekday, from: date) == restDay
    }
}
