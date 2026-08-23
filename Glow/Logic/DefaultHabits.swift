import Foundation

/// The habits a fresh install starts with.
///
/// Habits and nothing else: a tracker opening with a streak you did not earn
/// is lying to you on the first screen, so every install begins with an empty
/// grid. The invented past that shows the design off is `DemoHistory`, behind
/// a toggle in Settings — asked for, never assumed.
///
/// They are ordinary habits, editable and deletable like any other. The point
/// is that the first launch shows what the grid is for, rather than an empty
/// state and a plus button.
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
    /// `Gratitude` and `Early night` say `.daily` rather than
    /// `.timesPerWeek(7)`: `Frequency.init(timesPerWeek:)` folds seven into
    /// `.daily` at runtime, so the literal may as well say what it means.
    static let all: [Template] = [
        // Eight, in three clusters by time of day. Morning:
        Template(name: "Gratitude", icon: "pencil", frequency: .daily),
        Template(name: "Stretch", icon: "figure.yoga", frequency: .timesPerWeek(4)),
        Template(name: "Read Book", icon: "book", frequency: .timesPerWeek(4)),

        Template(isSpacer: true, name: "", icon: "", frequency: .daily),

        // Midday:
        Template(name: "Workout", icon: "dumbbell", frequency: .timesPerWeek(3)),
        Template(name: "VO2 Max", icon: "figure.run", frequency: .timesPerWeek(2)),
        Template(name: "Tutorial", icon: "play.rectangle", frequency: .timesPerWeek(3)),

        Template(isSpacer: true, name: "", icon: "", frequency: .daily),

        // Evening:
        Template(name: "Watch Sunset", icon: "sunset", frequency: .timesPerWeek(3)),
        Template(name: "Early night", icon: "bed.double", frequency: .daily)
    ]
}
