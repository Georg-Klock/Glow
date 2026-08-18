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
}
