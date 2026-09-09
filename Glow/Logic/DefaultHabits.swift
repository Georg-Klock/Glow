import Foundation

/// The curated set — the habits a fresh install can choose to start with.
///
/// **Offered, not installed** (#228). This list used to arrive on first launch
/// unasked, and it arrives on the empty state's second button now; the list is
/// unchanged, the tap in front of it is new. `HabitStore.resetToDefaults` is
/// the one call that puts it in, from there and from Settings' reset.
///
/// Habits and nothing else: a tracker opening with a streak you did not earn
/// is lying to you on the first screen, so the set arrives with an empty grid.
/// The invented past that shows the design off is `DemoHistory`, behind a
/// toggle in Settings — asked for, never assumed.
///
/// They are ordinary habits, editable and deletable like any other, which is
/// what the empty state says before the tap rather than after it.
enum DefaultHabits {
    struct Template {
        /// A blank row rather than a habit. Everything else is ignored.
        var isSpacer = false
        let name: String
        let icon: String
        let frequency: Frequency
    }

    /// One list, one screen.
    ///
    /// It was one list and two: five per-day habits rode along at the end for
    /// the Today ring, and the split happened on the way out. Both are gone with
    /// the kind they served (#209) — Sunlight, Protein Meal, Move, Breathe and
    /// Hydration are on `feature/daily-habits-2.0`, and an install that already
    /// has them is swept by `DailyHabitMigration`.
    ///
    /// **Blank rows are the grid's own device.** Two of them, because three
    /// clusters need two dividers — not because a target row count wanted
    /// filling. Eight habits and two blank rows is ten, inside the large
    /// widget's eleven.
    ///
    /// Names are short on purpose. The label column is a fixed fraction of the
    /// width, and a long name truncates on a small phone, which is a poor first
    /// impression for a screen whose whole claim is that it reads at a glance.
    ///
    /// **Every name carries its week's count as a literal prefix.** A row draws
    /// its cadence as the shape of its marks, which is exact but has to be
    /// counted; the seed set says the number outright, so the first screen
    /// reads "3x Workout" rather than asking anyone to count three sockets.
    ///
    /// It is a *literal*, and nothing keeps it honest. The name is stored,
    /// editable and deletable like any other habit's, and no code here reads
    /// the `frequency` beside it — so a habit re-targeted to 5×/week goes on
    /// calling itself "3x Workout" until its owner renames it. That is the
    /// accepted cost of writing the number into the name instead of deriving
    /// it as a display element: a future reader should take the prefix as the
    /// text this set happened to ship with, not as a fact about the row.
    ///
    /// **Two names shortened to make room** (#613). Prefixed, "4x Read Book"
    /// measures 77.80pt and "7x Early night" 76.23pt against the 71.75pt name
    /// column (`WidgetMetrics.nameMaxWidth`, at the row's own 12pt) — both
    /// would have shipped truncated on a screen whose first impression is the
    /// whole point. `Reading` and `Bedtime` are the same habits at 63.12pt and
    /// 63.00pt. `SeedingTests` reads the names back off this list rather than
    /// pinning literals, and measures every one of them against the column at
    /// every phone width, so the next edit here cannot reintroduce a cut.
    ///
    /// `Gratitude` and `Bedtime` say `.daily` rather than `.timesPerWeek(7)`:
    /// `Frequency.init(timesPerWeek:)` folds seven into `.daily` at runtime, so
    /// the literal may as well say what it means. Their prefix is `7x` because
    /// that is the week `.daily` asks for.
    static let all: [Template] = [
        // Eight, in three clusters by time of day. Morning:
        Template(name: "7x Gratitude", icon: "pencil", frequency: .daily),
        Template(name: "4x Stretch", icon: "figure.yoga", frequency: .timesPerWeek(4)),
        Template(name: "4x Reading", icon: "book", frequency: .timesPerWeek(4)),

        Template(isSpacer: true, name: "", icon: "", frequency: .daily),

        // Midday:
        Template(name: "3x Workout", icon: "dumbbell", frequency: .timesPerWeek(3)),
        Template(name: "2x VO2 Max", icon: "figure.run", frequency: .timesPerWeek(2)),
        Template(name: "3x Tutorial", icon: "play.rectangle", frequency: .timesPerWeek(3)),

        Template(isSpacer: true, name: "", icon: "", frequency: .daily),

        // Evening:
        Template(name: "3x Sunset", icon: "sunset", frequency: .timesPerWeek(3)),
        Template(name: "7x Bedtime", icon: "bed.double", frequency: .daily)
    ]
}
