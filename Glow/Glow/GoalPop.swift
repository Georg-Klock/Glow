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
/// **One pool, and one line per tap** (#420, 2026-08-29). This type used to
/// hold two vocabularies and argue for them:
///
/// > Two vocabularies, so the rare thing still reads as rarer. A repetition
/// > gets a plain acknowledgement; a goal met gets the celebratory one.
/// > Sharing a list would have made the goal indistinguishable from the
/// > twelfth glass of water.
///
/// That is reversed, and the paragraph is quoted rather than left standing
/// because it is the argument anyone will re-derive. What it got wrong is that
/// the register was doing two unrelated jobs at once: picking a vocabulary,
/// *and* gating how often the Island speaks. Only the second one was carrying
/// the "rarer" claim, and the switch below still does it — **Goals** is the
/// setting that makes the goal the only thing spoken. The vocabularies were
/// paying for it a second time, at the price of a six-word list that a person
/// logging twice a day exhausts inside a week.
///
/// It also made one tap say two things. The goal-completing tap fired the
/// routine line and then replaced it with the goal's part-way through a
/// two-second window — a handover nobody asked for, and the only place in the
/// app where a single tap produced two pops. One tap, one line, and the pool
/// is wide enough that repetition is what makes a phrase rare rather than
/// which list it came from. See docs/decisions.md.
enum GoalPop {
    /// Everything the pop can say. 173 phrases, one pool.
    ///
    /// **Fourteen characters is a measurement, not a style rule** (#310). The
    /// compact Island region cannot carry fifteen characters at any pushed
    /// size: the previous list's "that's the week" survived there only on
    /// `minimumScaleFactor(0.6)`, and nothing in this set leans on that floor.
    /// `GoalPopTests` holds the budget, because the next batch of phrases is
    /// what would put the problem back.
    ///
    /// Lowercase throughout, and a clean set: this appears over whatever else
    /// is on screen, and it keeps the app at 4+.
    static let lines = [
        "yes slay",
        "ate that",
        "no notes",
        "certified icon",
        "devoured it",
        "iconic",
        "legend",
        "pr energy",
        "beast mode",
        "new pr",
        "locked in",
        "lockout",
        "gains secured",
        "iron sharpened",
        "set complete",
        "gg",
        "clutch",
        "unlocked",
        "level up",
        "s-tier",
        "high score",
        "boss cleared",
        "xp secured",
        "clean landing",
        "nailed it",
        "stuck it",
        "rolling clean",
        "full send",
        "smooth line",
        "undefeated",
        "champion",
        "full distance",
        "takedown",
        "still standing",
        "little win",
        "bread's rising",
        "nurtured that",
        "cozy win",
        "big w",
        "the way",
        "understood",
        "chef's kiss",
        "certified w",
        "sent it",
        "big win",
        "home run",
        "all net",
        "match point",
        "first down",
        "photo finish",
        "banger",
        "on beat",
        "encore worthy",
        "clean drop",
        "shipped it",
        "zero bugs",
        "compiled clean",
        "deployed",
        "all green",
        "look at you",
        "that's enough",
        "crushing it",
        "you showed up",
        "well earned",
        "well plated",
        "well seasoned",
        "done right",
        "recipe nailed",
        "ignition",
        "orbit achieved",
        "liftoff",
        "touchdown",
        "summit reached",
        "in stride",
        "trail cleared",
        "fresh fit",
        "cop that win",
        "heat confirmed",
        "grail unlocked",
        "new high score",
        "game won",
        "insert win",
        "quest complete",
        "loot earned",
        "legend status",
        "level cleared",
        "treasure found",
        "smooth sailing",
        "x marks it",
        "rode it out",
        "saddled up",
        "reined it in",
        "full house",
        "ace played",
        "called it",
        "encore please",
        "ovation",
        "clear skies",
        "storm cleared",
        "earned calm",
        "new growth",
        "bloomed",
        "roots deeper",
        "perfect brew",
        "well steeped",
        "wonderful",
        "checkmate",
        "good move",
        "endgame",
        "new pace",
        "miles logged",
        "crossed it",
        "chain's tight",
        "on cadence",
        "you got this",
        "clean stroke",
        "personal best",
        "touched first",
        "topped out",
        "held the line",
        "bullseye",
        "on target",
        "arrow's true",
        "course held",
        "docked clean",
        "smooth harbor",
        "clean & simple",
        "you're winning",
        "love it",
        "harvest is in",
        "field tended",
        "crop is strong",
        "godspeed",
        "mission done",
        "code cracked",
        "pulled it off",
        "ta-da",
        "saved the day",
        "power move",
        "nicely done",
        "case closed",
        "here we go",
        "solved it",
        "no net needed",
        "balanced",
        "stars aligned",
        "you did it",
        "yeah",
        "fire's lit",
        "done & dusted",
        "strike",
        "pins cleared",
        "perfect frame",
        "awesome",
        "right on mark",
        "reeled it in",
        "good catch",
        "line held",
        "on tempo",
        "in step",
        "hit that mark",
        "go get it",
        "there it is",
        "that's the one",
        "well done",
        "keep going",
        "nice work",
        "way to go",
        "solid work",
        "good on you",
        "right on",
        "onward",
        "proud of you",
    ]

    /// One line, drawn fresh.
    ///
    /// Random per pop, not hashed from the habit and the day. The seed made
    /// one habit say exactly one thing all day however many times it was
    /// toggled, and with 173 phrases in the pool that is what a person
    /// actually notices (#450).
    ///
    /// #420 argued the opposite and gave a reason: a Live Activity's content
    /// can be re-read, so a phrase that changed under the reader would look
    /// like a glitch. **That risk is handled by the architecture, not by the
    /// seed.** Both surfaces choose once and store the result —
    /// `GoalPopAttributes.ContentState` holds the chosen `line` and the
    /// Activity renders from it, and the in-app pop holds its own — so nothing
    /// recomputes a phrase while it is on screen. Stability under re-read was
    /// never what the arithmetic was buying.
    ///
    /// Takes no habit and no day, because it no longer depends on either.
    static func line() -> String {
        lines.randomElement() ?? ""
    }

    /// The longest a line may be, in characters.
    ///
    /// #310's measurement of the compact Island region, kept beside the list
    /// it constrains rather than in a test file, so the next person adding
    /// phrases finds the number where the phrases are.
    static let maximumLineLength = 14

    /// How long it stays. Long enough to read, short enough not to be a
    /// notification — this is a pop, and a Live Activity is a session that ends
    /// almost immediately.
    ///
    /// Two seconds is also a **correctness** bound, not only a taste one: the
    /// process that requested the pop is what ends it, and a widget tap's
    /// process loses its background assertion well before 30s. See
    /// docs/decisions.md and #102.
    ///
    /// **Kept when the handover went** (#420). This bounds *one* pop, and
    /// `PopWindow` below settles two different taps landing inside it. Neither
    /// had anything to do with one tap saying two things; removing them with
    /// the handover would reintroduce #102.
    static let duration: Duration = .seconds(2)
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
        /// people need encouragement, and the pool is 173 phrases wide (#420)
        /// precisely so frequent acknowledgement does not wear out. #185 gave
        /// that job to a separate quiet register; the width does it now, and
        /// does it for the goal-completing tap too. An install that already
        /// stored `1` under the old boolean scheme is a different question:
        /// see `goals`.
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

    /// Whether this tap's pop should fire at all.
    ///
    /// Pure, and the only place the rule lives — both call sites ask rather
    /// than deciding, so "what does the switch mean" is one testable answer.
    ///
    /// **Written against the goal, not against a register** (#420). This used
    /// to take a `GoalPop.Register`, which made the three-way switch look like
    /// it depended on the two vocabularies. It never did: the register was
    /// gating frequency and picking words in one type, and only the frequency
    /// half is what **Never / Goals / Everything** means. The boolean is the
    /// one both call sites already compute on their first line, from
    /// `GoalMet.justMet(habit:in:)`, so nothing new is plumbed to get it here.
    ///
    /// **One answer, not a list**, which is where "never fires twice" actually
    /// lives. A tap that meets the goal used to get a two-element sequence out
    /// of here and play it with a handover in between. A `Bool` cannot express
    /// that, so the double-fire is gone by construction rather than by a guard
    /// somebody has to remember to keep.
    static func allows(justMetGoal: Bool, at level: Level) -> Bool {
        switch level.effective {
        case .off: false
        case .goals: justMetGoal
        case .everything, .unset: true
        }
    }

    static func allows(justMetGoal: Bool) -> Bool {
        allows(justMetGoal: justMetGoal, at: level)
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
