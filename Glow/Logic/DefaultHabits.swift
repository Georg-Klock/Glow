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

    /// One list, two screens.
    ///
    /// `Frequency` has two kinds that never share a surface, and each screen
    /// asks its own question of the store: This Week queries
    /// `Habit.countedPerWeek` and Today queries `Habit.countedPerDay`. So the
    /// seed is written as one array in one order, and the split happens on the
    /// way out rather than here — eight weekly-cadence habits for the grid,
    /// five per-day habits for the ring.
    ///
    /// **Blank rows are the grid's own device** and only ever land there:
    /// `countedPerWeek` is `timesPerDay == 0`, which a spacer satisfies and a
    /// per-day habit never does. Two of them, because three clusters need two
    /// dividers — not because a target row count wanted filling. Eight habits
    /// and two blank rows is ten, inside the large widget's eleven.
    ///
    /// Names are short on purpose. The label column is a fixed fraction of the
    /// width, and a long name truncates on a small phone, which is a poor first
    /// impression for a screen whose whole claim is that it reads at a glance.
    ///
    /// `Gratitude` and `Early night` say `.daily` rather than
    /// `.timesPerWeek(7)`: `Frequency.init(timesPerWeek:)` folds seven into
    /// `.daily` at runtime, so the literal may as well say what it means.
    static let all: [Template] = [
        // The weekly eight, in three clusters by time of day. Morning:
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
        Template(name: "Early night", icon: "bed.double", frequency: .daily),

        // The per-day five, which never reach the grid — they are Today's
        // rings. Counts rather than checkmarks, because that is the cadence
        // each of these actually has: water is drunk across a day, not logged
        // once at the end of it.
        Template(name: "Sunlight", icon: "sun.max", frequency: .timesPerDay(2)),
        Template(name: "Protein Meal", icon: "fork.knife", frequency: .timesPerDay(3)),
        Template(name: "Move", icon: "figure.walk", frequency: .timesPerDay(4)),
        Template(name: "Breathe", icon: "wind", frequency: .timesPerDay(3)),
        Template(name: "Hydration", icon: "drop", frequency: .timesPerDay(8))
    ]

    /// The rows This Week and the week widget see: the weekly cadences and the
    /// blank rows between them, in order.
    static var weekly: [Template] { all.filter { !$0.frequency.isCountedPerDay } }

    /// The rows Today sees. Blank rows are the grid's, so none are here.
    static var perDay: [Template] { all.filter(\.frequency.isCountedPerDay) }
}
