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
    static let all: [Template] = [
        Template(name: "Workout", icon: "figure.run", frequency: .daily),
        Template(name: "Stretch", icon: "figure.flexibility", frequency: .daily),
        Template(name: "Study", icon: "book", frequency: .daily),
        Template(name: "Early night", icon: "bed.double", frequency: .timesPerWeek(2)),
        Template(name: "Hydration", icon: "drop", frequency: .daily),
        Template(name: "Touch Grass", icon: "leaf", frequency: .daily),
        Template(name: "Touch Grass", icon: "leaf", frequency: .timesPerWeek(2)),
        Template(name: "Watch Sunset", icon: "sunrise", frequency: .timesPerWeek(1)),

        // Three blank rows, which take the set to the eleven a large widget
        // holds. They are here to be *moved*: drag one between two habits and
        // the grid clusters into morning, midday and evening without the app
        // needing sections, headers, or a second kind of grouping to keep in
        // step with the order.
        Template(isSpacer: true, name: "", icon: "", frequency: .daily),
        Template(isSpacer: true, name: "", icon: "", frequency: .daily),
        Template(isSpacer: true, name: "", icon: "", frequency: .daily)
    ]
}
