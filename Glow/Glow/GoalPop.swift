import ActivityKit
import Foundation

/// What the Dynamic Island says when something is logged, and the switch that
/// governs it.
///
/// **This is not a mark.** SPEC §3 lists celebratory flourishes as a non-goal,
/// and the reason is real: the app has one signal, brightness, and it means
/// *this happened*. A pop is outside the grid, lasts two seconds and records
/// nothing — the one-rule invariant is about the surfaces that keep state, and
/// this keeps none. That argument is unchanged and still the reason there is no
/// badge, no streak and no second colour.
///
/// **What changed is how often it speaks** (#119). This type used to open:
///
/// > The line the Dynamic Island says when a goal is met…
///
/// and `GoalMet` argued the restriction directly — "firing on every completion
/// would put twenty of these a day on a screen whose whole argument is that it
/// says one thing". That reasoning is kept here rather than deleted, because it
/// is the argument anyone will re-derive: the answer is that a pop is not on
/// that screen. It is two seconds over the Island, on the home screen, and it
/// leaves nothing behind — so its frequency is a question about how often a
/// person wants to be spoken to, which is a preference, not an invariant. It is
/// a three-way switch now, and the person decides.
///
/// **Two vocabularies, so the rare thing still reads as rarer.** A repetition
/// gets a plain acknowledgement; a goal met gets the celebratory one. Sharing a
/// list would have made the goal indistinguishable from the twelfth glass of
/// water, which is the failure the old restriction was really guarding against.
enum GoalPop {
    /// Which vocabulary a line is drawn from.
    enum Register {
        /// One repetition, or one day, logged. The routine case.
        case logged
        /// The day's or the week's goal met. The rare one.
        case goal
    }

    /// The routine acknowledgement. Flat on purpose: this is the line a person
    /// may see several times a day, and a phrase that congratulates them for a
    /// third of a habit wears out by lunchtime.
    static let lines = [
        "logged",
        "nice one",
        "there it is",
        "done",
        "got it",
        "counted",
    ]

    /// The goal's own vocabulary, and the reason the routine one is flat.
    ///
    /// Short is a hard constraint rather than a style preference: a compact
    /// Island state has very little room, and anything that does not fit is
    /// truncated by the system rather than wrapped.
    ///
    /// Clean set only, both lists. This appears over whatever else is on screen,
    /// and it keeps the app at 4+.
    static let goalLines = [
        "you did it",
        "awesome",
        "go get it",
        "that's the one",
        "well played",
        "that's the week",
    ]

    static func lines(for register: Register) -> [String] {
        switch register {
        case .logged: lines
        case .goal: goalLines
        }
    }

    /// One line, chosen deterministically.
    ///
    /// The same completion must say the same thing every time it is rendered:
    /// a Live Activity's content can be re-read, and a phrase that changed
    /// under the reader would read as a glitch. Hashed from the habit and the
    /// day rather than random, so it is stable without storing anything.
    ///
    /// The register is not part of the seed, so the goal-completing tap draws
    /// the *same index* from a different list — which is what makes the pair
    /// read as one moment rather than two unrelated phrases.
    static func line(
        habitID: UUID,
        on day: Date,
        register: Register,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        var seed = UInt64(truncatingIfNeeded: habitID.hashValue)
        seed = seed &* 31 &+ UInt64(truncatingIfNeeded: parts.year ?? 0)
        seed = seed &* 31 &+ UInt64(truncatingIfNeeded: parts.month ?? 0)
        seed = seed &* 31 &+ UInt64(truncatingIfNeeded: parts.day ?? 0)
        let vocabulary = lines(for: register)
        return vocabulary[Int(seed % UInt64(vocabulary.count))]
    }

    /// How long it stays. Long enough to read, short enough not to be a
    /// notification — this is a pop, and a Live Activity is a session that ends
    /// almost immediately.
    ///
    /// Two seconds is also a **correctness** bound, not only a taste one: the
    /// process that requested the pop is what ends it, and a widget tap's
    /// process loses its background assertion well before 30s. See
    /// docs/decisions.md and #102.
    /// The registers one completion has to say, in the order it says them,
    /// before preferences are asked.
    ///
    /// **Shared by both surfaces** (#273). The Island's pop and the app's own
    /// say the same words for the same tap, and used to decide that separately
    /// — `GoalPopCentre` had the only copy while the app deliberately said
    /// nothing. Now that the app pops too, one rule keeps them from drifting
    /// into disagreeing about what a tap means.
    ///
    /// The tap that meets the goal has two things to say (#119), and they share
    /// the two seconds rather than getting one each: a compact Island state has
    /// room for one short phrase, so "logged" hands over to "you did it"
    /// partway through.
    static func registers(justMetGoal: Bool) -> [Register] {
        justMetGoal ? [.logged, .goal] : [.logged]
    }

    static let duration: Duration = .seconds(2)

    /// How long the routine line holds before a goal-completing tap replaces it.
    ///
    /// The tap that meets the goal has two things to say, and they share the
    /// two seconds rather than getting one each: "logged", then "you did it".
    /// Sequential rather than combined, because a compact Island state has room
    /// for one short phrase and not for two.
    static let handover: Duration = .milliseconds(700)
}

/// How much the Island says.
///
/// **Default on at `goals`, and that is the part with a trap in it.**
/// `@AppStorage` hands back `false` — and `0` — for a key nobody has written,
/// so a plain default of "on" reads as *off* for everybody until they change it
/// twice. Stored the way `WeekPreferences.restDay` handles "unset": an explicit
/// sentinel behind a computed property, and `unset` is `0` for exactly that
/// reason.
///
/// In the App Group's defaults, because the intents that fire it may run in a
/// different process from the app and would otherwise read a different store.
///
/// **Three states rather than two** (#119). `goals` is what the switch used to
/// mean by "on" and stays the default, so nobody's setting changes underneath
/// them: the stored `1` that meant on still means goals. `everything` is the new
/// one, and it is opt-in because being spoken to on every tap is a preference
/// some people will want and most will not.
enum PopPreferences {
    static let key = "islandPop"

    enum Level: Int, CaseIterable, Identifiable {
        /// Never written. Reads as `everything` for a fresh install (#185) —
        /// people need encouragement, and a repetition now has its own quieter
        /// register (`logged`, `counted`, `got it`) precisely so frequent
        /// acknowledgement does not wear out the way it would have before #119
        /// gave it one. An install that already stored `1` under the old
        /// boolean scheme is a different question: see `goals`.
        case unset = 0
        /// Only when the day's or the week's goal is met. Never the default
        /// for a new install any more, but still what a *stored* `1` means —
        /// the value "on" wrote before there were three levels, and that
        /// install's setting does not change underneath it just because the
        /// default facing a new one did.
        case goals = 1
        case off = 2
        /// Every repetition, and the goal on top of it.
        case everything = 3

        var id: Int { rawValue }

        /// What a stored value means, with `unset` resolved.
        var effective: Level { self == .unset ? .everything : self }
    }

    static var level: Level {
        get {
            let stored = GlowSettings.store.object(forKey: key) as? Int ?? Level.unset.rawValue
            return (Level(rawValue: stored) ?? .unset).effective
        }
        set { GlowSettings.store.set(newValue.effective.rawValue, forKey: key) }
    }

    /// Whether a pop of this register should fire at all.
    ///
    /// Pure, and the only place the rule lives — `GoalPopCentre` asks rather
    /// than deciding, so "what does the switch mean" is one testable answer.
    static func allows(_ register: GoalPop.Register, at level: Level) -> Bool {
        switch level.effective {
        case .off: false
        case .goals: register == .goal
        case .everything, .unset: true
        }
    }

    static func allows(_ register: GoalPop.Register) -> Bool {
        allows(register, at: level)
    }

    /// Kept so nothing outside has to know about three states to ask the one
    /// question most callers want: is the Island going to say anything at all?
    static var isEnabled: Bool { level != .off }
}

/// What the Island is showing.
struct GoalPopAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The habit whose goal was met, so the pop says *which*.
        var habitName: String
        /// The line, chosen once when the activity is requested.
        var line: String
    }

    /// **Deliberately empty.** This used to be `habitID`, on the reasoning that
    /// a second goal met while the first was still up should queue as its own
    /// activity rather than replace it. Measured, and it does not queue: two
    /// activities live at once and the Island renders only the newest, so the
    /// first habit's line is drawn, hidden, and ended on a timer nobody saw
    /// start. See #102.
    ///
    /// One activity, whose words change, is the same thing on screen with one
    /// timer and no invisible second session — and it makes the behaviour this
    /// app's rather than a side effect of how the Island stacks.
}

/// Which scheduled ending is allowed to fire.
///
/// With one shared activity, every pop schedules an end — and the first tap's
/// end would land two seconds after *its* tap, cutting short a pop a later goal
/// had just refreshed. So each pop takes a number, and only the newest may end
/// the activity.
///
/// Pure, and separate from `GoalPopCentre`, because this is the part that can
/// actually be wrong: the rest is ActivityKit calls with nothing to decide.
enum PopWindow {
    static func shouldEnd(scheduled: Int, latest: Int) -> Bool {
        scheduled == latest
    }
}
