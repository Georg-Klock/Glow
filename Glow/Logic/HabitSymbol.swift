import Foundation

/// The icons a habit can have.
///
/// SF Symbols rather than free-text emoji, which is a change from the original
/// plan. Emoji is less work, but it renders at whatever weight and colour the
/// font vendor chose, ignores the accent, ignores Dynamic Type's optical
/// sizing, and reads as a sticker next to system typography. A symbol inherits
/// all of it.
///
/// The stored value is still a plain string, so nothing has to migrate: a habit
/// created before this change holds an emoji, `isSymbol` says so, and the view
/// renders it as text.
enum HabitSymbol {
    static let `default` = "checkmark.circle"

    /// A small curated set. A full symbol browser is a different feature, and
    /// this is a habit tracker, so the list covers what people track rather
    /// than everything Apple ships.
    static let catalog: [(section: String, symbols: [String])] = [
        ("Health", [
            "figure.run", "figure.walk", "figure.strengthtraining.traditional",
            "figure.yoga", "figure.pool.swim", "bicycle",
            "heart", "lungs", "pills", "bed.double"
        ]),
        ("Mind", [
            "book", "brain.head.profile", "pencil.and.scribble", "text.book.closed",
            "graduationcap", "lightbulb", "music.note", "paintbrush"
        ]),
        ("Daily", [
            "drop", "carrot", "fork.knife", "cup.and.saucer",
            "sun.max", "moon.stars", "leaf", "camera"
        ]),
        ("Other", [
            "checkmark.circle", "star", "flame", "sparkles",
            "phone", "envelope", "house", "dog"
        ])
    ]

    static let all: [String] = catalog.flatMap(\.symbols)

    /// Whether a stored icon should be drawn as a symbol or as plain text.
    ///
    /// Anything in the catalogue is a symbol. Anything else is treated as text,
    /// which covers both the emoji habits created before this change and any
    /// symbol name that a future OS stops shipping.
    static func isSymbol(_ icon: String) -> Bool {
        all.contains(icon)
    }
}
