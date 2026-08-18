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

    /// A deliberate mix of cadences, so both row shapes are on screen at once
    /// and the difference between seven circles and N pills is visible without
    /// having to go and create it.
    ///
    /// Names are kept short on purpose. The label column is a fixed fraction of
    /// the width, and "Drink water" truncates to "Drink wa..." on a small phone,
    /// which is a poor first impression for a screen whose whole claim is that
    /// it is readable at a glance.
    static let all: [Template] = [
        Template(name: "Read", icon: "book", frequency: .daily),
        Template(name: "Water", icon: "drop", frequency: .daily),
        Template(name: "Exercise", icon: "figure.run", frequency: .timesPerWeek(3)),
        Template(name: "Stretch", icon: "figure.flexibility", frequency: .timesPerWeek(4)),
        Template(name: "Outside", icon: "leaf", frequency: .daily),
        Template(name: "Early night", icon: "bed.double", frequency: .timesPerWeek(5))
    ]
}
