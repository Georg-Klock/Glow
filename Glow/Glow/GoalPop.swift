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
    /// Everything the pop can say. 370 phrases, one pool.
    ///
    /// **Nine varieties of English, on purpose** (#471). The list opened as one
    /// register — themed and a little arch, with plain speech a tail of about
    /// seventeen — so a draw rarely landed on anything a person would actually
    /// say out loud. It now runs from plain American through British, Irish,
    /// Australian, New Zealand, Scottish, Welsh, South African, Indian and
    /// Caribbean English, including words those Englishes have naturalised from
    /// other languages: `ka pai`, `shabash`, `kya baat`, `lekker`, `aweh`,
    /// `irie`.
    ///
    /// **Regional is the point; famous-for-being-regional is not.** The phrases
    /// outsiders quote were considered and left out — `lovely jubbly`,
    /// `tickety-boo`, `jolly good`, `top banana`, `bonza`, `bonzer`,
    /// `fair dinkum` — because a catchphrase reads as an impression of a place
    /// rather than a voice from it. `mean` went with them for a different
    /// reason: it is high praise in New Zealand and an insult everywhere else,
    /// and this pool has no locale to disambiguate it. `mean as` is unambiguous
    /// and stayed.
    ///
    /// **Nothing gendered.** `attaboy`, `attagirl`, `good lad`, `good lass`,
    /// `good man`, `boet` and `bro` are all natural in these registers and all
    /// absent. `mate` is the one term of address here that reads neutral, and
    /// `atta way` is the neutral form of the first pair.
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

        // Plain English — the register the pool was thinnest in.
        "good job",
        "nice job",
        "great job",
        "good one",
        "good going",
        "nice going",
        "good work",
        "good stuff",
        "very nice",
        "real nice",
        "doing great",
        "doing good",
        "looking good",
        "way to be",
        "good hustle",
        "nice hustle",
        "atta way",
        "there you go",
        "there ya go",
        "there we go",
        "there we are",
        "there now",
        "that's it",
        "that's right",
        "you got it",
        "got it champ",
        "you bet",
        "keep it up",
        "keep at it",
        "keep rolling",
        "stay with it",
        "carry on",
        "got it done",
        "did the thing",
        "job well done",
        "take a bow",
        "hats off",
        "in the books",
        "on the board",
        "chalk it up",
        "count it",
        "another one",
        "one more done",
        "and again",
        "adds up",
        "it all counts",
        "bit by bit",
        "day by day",
        "step by step",
        "easy does it",
        "good for you",
        "you earned it",
        "not bad",
        "not bad at all",
        "all good",
        "that'll do",
        "well alright",
        "alright then",
        "look at that",
        "how about that",
        "worth it",
        "handled",
        "taken care of",
        "done and done",
        "honest work",
        "steady work",
        "first rate",
        "top notch",
        "outstanding",
        "excellent",
        "perfect",
        "lovely",
        "beautiful",
        "smooth",
        "solid",
        "on a roll",
        "put in work",
        "way to show up",
        "showed up",

        // British.
        "brilliant",
        "smashing",
        "cracking",
        "cracking stuff",
        "lovely stuff",
        "spot on",
        "bang on",
        "top marks",
        "top drawer",
        "first class",
        "good show",
        "marvellous",
        "splendid",
        "very good",
        "sound",
        "sound as",
        "quality",
        "class",
        "ace",
        "magic",
        "belter",
        "belting",
        "mint",
        "wicked",
        "proper job",
        "tidy",
        "chuffed",
        "well chuffed",
        "good effort",
        "top effort",
        "solid effort",
        "good graft",
        "hard graft",
        "graft",
        "fair play",
        "fair dos",
        "get in",
        "well in",
        "get in there",
        "smashed it",
        "nailed on",
        "not half bad",
        "sorted",
        "job done",
        "well sorted",
        "nice one mate",
        "well in mate",
        "decent",
        "very decent",
        "respect",
        "have it",
        "grand",
        "smart",
        "canny",
        "banging",

        // Irish.
        "deadly",
        "savage",
        "mighty",
        "fair dues",
        "grand job",
        "grand stuff",
        "great stuff",
        "cracker",
        "lovely hurling",
        "no bother",
        "not a bother",
        "keep her lit",
        "sure look",
        "happy days",
        "flying it",
        "you're flying",
        "ah lovely",
        "well done you",

        // Australian.
        "good on ya",
        "good onya",
        "onya",
        "too easy",
        "beauty",
        "you beauty",
        "ripper",
        "little ripper",
        "top stuff",
        "great effort",
        "ace effort",
        "well done mate",
        "not bad mate",
        "spot on mate",
        "stoked",
        "beaut",

        // New Zealand.
        "sweet as",
        "choice",
        "mean as",
        "hard out",
        "good as gold",
        "ka pai",
        "chur",
        "tumeke",
        "flash",

        // Scottish.
        "braw",
        "nae bother",
        "pure class",
        "no bad",
        "away ye go",

        // Welsh.
        "lush",
        "there's lovely",

        // South African.
        "lekker",
        "sharp sharp",
        "kiff",
        "aweh",

        // Indian English.
        "shabash",
        "kya baat",
        "superb",
        "too good",
        "wah",

        // Caribbean.
        "irie",
        "big up",
        "bless up",
        "respect due",
    ]

    /// One line from a persisted shuffle bag.
    ///
    /// Random per cycle, not hashed from the habit and the day. The seed made
    /// one habit say exactly one thing all day however many times it was
    /// toggled (#450); independent random draws fixed that while still making
    /// an immediate repeat possible and leaving some phrases unseen for an
    /// arbitrarily long time. The bag makes the promise exact: all 173 lines
    /// appear once before any appears again (#452).
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
    /// The unseen indices and an exact marker for this pool live in the App
    /// Group defaults, so app and widget spend the same cycle. A pool edit
    /// invalidates the bag instead of interpreting old indices against new
    /// words. Takes no habit and no day, because it depends on neither.
    static func line() -> String {
        lineLock.lock()
        defer { lineLock.unlock() }

        var generator = SystemRandomNumberGenerator()
        return ShuffleBag(lines: lines, store: GlowSettings.store).draw(using: &generator)
    }

    /// Serialises the read-modify-write inside one process. App Group defaults
    /// cannot make that operation atomic across the app and widget processes;
    /// two taps landing in that tiny window can still spend the same index,
    /// which is an accepted rare race rather than a second buffering system.
    private static let lineLock = NSLock()

    /// The persisted part of phrase selection, separated only far enough for
    /// deterministic tests to supply a generator and a private defaults suite.
    struct ShuffleBag {
        static let remainingKey = "goalPopShuffleRemainingIndices"
        static let poolMarkerKey = "goalPopShufflePoolMarker"

        let lines: [String]
        let store: UserDefaults

        func draw<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
            guard !lines.isEmpty else { return "" }

            let markerMatches = store.stringArray(forKey: Self.poolMarkerKey) == lines
            let stored = store.array(forKey: Self.remainingKey) as? [Int]
            var remaining: [Int]

            if markerMatches, let stored, Self.isValid(stored, for: lines) {
                remaining = stored
            } else {
                remaining = Array(lines.indices).shuffled(using: &generator)
            }

            if remaining.isEmpty {
                remaining = Array(lines.indices).shuffled(using: &generator)
            }

            let index = remaining.removeLast()

            // Remaining first, marker second. If the process dies between the
            // two writes after a pool edit, the stale marker forces a rebuild;
            // the reverse order could bless old indices for the new pool.
            store.set(remaining, forKey: Self.remainingKey)
            if !markerMatches {
                store.set(lines, forKey: Self.poolMarkerKey)
            }

            return lines[index]
        }

        private static func isValid(_ indices: [Int], for lines: [String]) -> Bool {
            indices.count <= lines.count
                && Set(indices).count == indices.count
                && indices.allSatisfy(lines.indices.contains)
        }
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
