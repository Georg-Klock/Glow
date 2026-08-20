import Foundation

/// The habits a fresh install starts with.
///
/// **Habits, and a past.** This used to seed habits and nothing else, on the
/// reasoning that a tracker opening with a streak you did not earn is lying to
/// you on the first screen. That reasoning still holds and is written up in
/// SeededHistory, which is where the invented history lives and where the two
/// ways of switching it off are noted. What changed is the other side of it: an
/// empty grid shows none of what the app is for, and a design cannot be judged
/// against a blank slate.
///
/// Today is still never pre-filled.
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
        /// How this habit has been going over the seeded past.
        let form: SeededHistory.Form
        /// Fixed per habit, so the same install always shows the same past.
        let seed: UInt64
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
    /// **Each one arrives with a past.** See SeededHistory for why that is a
    /// trade rather than a free win. Two are perfect, so a full streak is on
    /// screen; the rest range down to patchy, so a missed day is on screen too.
    /// Today is never pre-filled — the open slot is the one thing the app is
    /// for, and seeding it would hide the feature on first launch.
    static let all: [Template] = [
        Template(name: "Workout", icon: "figure.run", frequency: .daily,
                 form: .strong, seed: 11),
        Template(name: "Stretch", icon: "figure.flexibility", frequency: .daily,
                 form: .perfect, seed: 22),
        Template(name: "Study", icon: "book", frequency: .daily,
                 form: .steady, seed: 33),
        Template(name: "Early night", icon: "bed.double", frequency: .timesPerWeek(2),
                 form: .strong, seed: 44),
        Template(name: "Hydration", icon: "drop", frequency: .daily,
                 form: .uneven, seed: 55),
        Template(name: "Touch Grass", icon: "leaf", frequency: .daily,
                 form: .steady, seed: 66),
        Template(name: "Touch Grass", icon: "leaf", frequency: .timesPerWeek(2),
                 form: .perfect, seed: 77),
        Template(name: "Watch Sunset", icon: "sunrise", frequency: .timesPerWeek(1),
                 form: .strong, seed: 88),

        // Three blank rows, which take the set to the eleven a large widget
        // holds. They are here to be *moved*: drag one between two habits and
        // the grid clusters into morning, midday and evening without the app
        // needing sections, headers, or a second kind of grouping to keep in
        // step with the order.
        Template(isSpacer: true, name: "", icon: "", frequency: .daily, form: .perfect, seed: 0),
        Template(isSpacer: true, name: "", icon: "", frequency: .daily, form: .perfect, seed: 0),
        Template(isSpacer: true, name: "", icon: "", frequency: .daily, form: .perfect, seed: 0)
    ]
}
