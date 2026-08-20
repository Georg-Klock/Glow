import SwiftUI

/// The app's one colour.
///
/// A slot is not identified by hue any more. It is identified by brightness:
/// empty, lit, or done. Committing to a single colour is what makes that
/// legible, because when six accents were in play the eye read colour first and
/// the glow second, which is backwards for an app whose whole signal is the
/// glow.
///
/// Slightly blue-ish white rather than pure white, because light sources read
/// as cool. A neutral white glow looks like a blown-out highlight; a cool one
/// looks lit.
enum GlowPalette {
    /// sRGB components, shared by the SwiftUI colour and the Core Image render
    /// so the solid shape and the HDR shape are the same colour.
    static let components: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0.85, 0.91, 1.0)

    static let color = Color(
        .sRGB,
        red: components.red,
        green: components.green,
        blue: components.blue,
        opacity: 1
    )

    /// The completed state. The same colour held back from full brightness, so
    /// done reads as "was lit" rather than as a different thing entirely.
    static let filled = Color(
        .sRGB,
        red: components.red * 0.82,
        green: components.green * 0.82,
        blue: components.blue * 0.82,
        opacity: 1
    )

    /// How far the halo carries beyond the slot, as a multiple of slot height.
    static let haloRadius: CGFloat = 0.55

    // MARK: - Brightness tiers
    //
    // Light means something happened. Every completion glows, whatever day it
    // fell on, and so does today's open slot — so a good week is a row of lights
    // and a bad one is nearly dark. What does *not* glow is anything that is
    // merely absent: a missed day and a day still to come are both flat.
    //
    // The one place emphasis still tracks "needs you now" is the label, which
    // steps back once its habit has been handled today.
    //
    // The multipliers are measured off the design rather than guessed.

    /// A habit still waiting on today: its icon and name, at full strength.
    static let labelDue = color
    /// A habit already handled today. Present, done asking.
    static let labelResting = color.opacity(0.56)

    /// A day that went unlogged. Faint, and the only mark drawn as a glyph
    /// rather than a shape — a miss should read as an absence, not an entry.
    static let missed = color.opacity(0.17)
    /// A day still to come: a solid disc, dark enough to be a socket rather
    /// than a mark. It is what makes the row legible as seven days when most of
    /// them are empty.
    static let upcoming = color.opacity(0.125)

    /// Today's letter in the weekday header.
    static let headerToday = color
    /// Every other letter.
    static let headerRest = color.opacity(0.35)

    /// Amber, and the only colour in the app that is not the glow. It is used
    /// for exactly one thing: saying that the glow is not available. A warning
    /// rendered in the app's own white would be indistinguishable from the
    /// thing it is warning about.
    static let warning = Color(.sRGB, red: 1.0, green: 0.72, blue: 0.22, opacity: 1)
}
