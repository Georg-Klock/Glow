import ActivityKit
import Foundation

/// The line the Dynamic Island says when a goal is met, and the switch that
/// turns it off.
///
/// **This is not a mark.** SPEC §3 lists celebratory flourishes as a non-goal,
/// and the reason is real: the app has one signal, brightness, and it means
/// *this happened*. A pop is outside the grid, lasts two seconds and records
/// nothing — the one-rule invariant is about the surfaces that keep state, and
/// this keeps none. See docs/decisions.md; the alternative reading, rewriting
/// §1 so that light may also mean well done, was declined.
enum GoalPop {
    /// The whole vocabulary. Short is a hard constraint rather than a style
    /// preference: a compact Island state has very little room, and anything
    /// that does not fit is truncated by the system rather than wrapped.
    ///
    /// Clean set only. This appears over whatever else is on screen, and it
    /// keeps the app at 4+.
    static let lines = [
        "you did it",
        "awesome",
        "go get it",
        "nice one",
        "that's the one",
        "well played",
    ]

    /// One line per goal met, chosen deterministically.
    ///
    /// The same completion must say the same thing every time it is rendered:
    /// a Live Activity's content can be re-read, and a phrase that changed
    /// under the reader would read as a glitch. Hashed from the habit and the
    /// day rather than random, so it is stable without storing anything.
    static func line(
        habitID: UUID,
        on day: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        var seed = UInt64(truncatingIfNeeded: habitID.hashValue)
        seed = seed &* 31 &+ UInt64(truncatingIfNeeded: parts.year ?? 0)
        seed = seed &* 31 &+ UInt64(truncatingIfNeeded: parts.month ?? 0)
        seed = seed &* 31 &+ UInt64(truncatingIfNeeded: parts.day ?? 0)
        return lines[Int(seed % UInt64(lines.count))]
    }

    /// How long it stays. Long enough to read, short enough not to be a
    /// notification — this is a pop, and a Live Activity is a session that ends
    /// almost immediately.
    static let duration: Duration = .seconds(2)
}

/// Whether the pop is switched on.
///
/// **Default on, and that is the part with a trap in it.** `@AppStorage` hands
/// back `false` for a key nobody has written, so a plain
/// `@AppStorage("pop") var on = true` reads as *off* for everybody until they
/// toggle it twice. Stored the way `WeekPreferences.restDay` handles "unset":
/// an explicit sentinel behind a computed property.
///
/// In the App Group's defaults, because the intents that fire it may run in a
/// different process from the app and would otherwise read a different store.
enum PopPreferences {
    static let key = "islandPop"

    /// 0 — never written, which means on. 1 on, 2 off.
    static let unset = 0
    static let on = 1
    static let off = 2

    static var isEnabled: Bool {
        get {
            let stored = GlowSettings.store.object(forKey: key) as? Int ?? unset
            return stored != off
        }
        set { GlowSettings.store.set(newValue ? on : off, forKey: key) }
    }
}

/// What the Island is showing.
struct GoalPopAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The habit whose goal was met, so the pop says *which*.
        var habitName: String
        /// The line, chosen once when the activity is requested.
        var line: String
    }

    /// Stable per habit, so a second goal met while the first is still up
    /// replaces nothing and queues as its own activity.
    var habitID: String
}
