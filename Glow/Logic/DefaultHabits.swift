import Foundation

/// The habits a fresh install starts with.
///
/// Habits, not history. Nothing here is completed and no past week is invented:
/// a tracker that opens showing a streak you did not earn is lying to you on
/// the first screen, and the one signal this app has is today's slot being
/// unfinished. So every seeded habit starts empty, and every one of them is
/// open today.
///
/// They are ordinary habits, editable and deletable like any other. The point
/// is that the first launch shows what the grid is for, rather than an empty
/// state and a plus button.
enum DefaultHabits {
    struct Template {
        let name: String
        let icon: String
        let frequency: Frequency
    }

    /// The set from the design file, in its order, with its icons and cadences.
    ///
    /// Taken literally rather than tidied, because these are what the design
    /// shows and the seed is the first screen anyone sees. Two things in it are
    /// worth knowing rather than quietly fixing:
    ///
    ///  - **Two habits called "Touch Grass"**, one daily and one twice a week.
    ///    In a mock that is how you show both row shapes side by side; in a real
    ///    install it is two rows nobody can tell apart.
    ///  - **"Watch Sunset" carries the `sunrise` symbol** — the arrow in the
    ///    file's glyph points up. Matched deliberately; `sunset` is one word away.
    ///
    /// Names are short on purpose. The label column is a fixed fraction of the
    /// width, and a long name truncates on a small phone, which is a poor first
    /// impression for a screen whose whole claim is that it reads at a glance.
    ///
    /// Habits, not history: see the note above. Nothing here is pre-completed.
    static let all: [Template] = [
        Template(name: "Workout", icon: "figure.run", frequency: .daily),
        Template(name: "Stretch", icon: "figure.flexibility", frequency: .daily),
        Template(name: "Study", icon: "book", frequency: .daily),
        Template(name: "Early night", icon: "bed.double", frequency: .timesPerWeek(2)),
        Template(name: "Hydration", icon: "drop", frequency: .daily),
        Template(name: "Touch Grass", icon: "leaf", frequency: .daily),
        Template(name: "Touch Grass", icon: "leaf", frequency: .timesPerWeek(2)),
        Template(name: "Watch Sunset", icon: "sunrise", frequency: .timesPerWeek(1))
    ]
}
