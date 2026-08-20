import SwiftUI

/// Every colour and every effect in the grid.
///
/// **Two colours.** White is anything lit; grey is anything that is not. There
/// is no third. A slot is never identified by hue — only by whether it is
/// glowing and, if not, how far down the grey scale it sits. That is what makes
/// the glow readable: when several accents were in play the eye read colour
/// first and the glow second, which is backwards for an app whose whole signal
/// is the glow.
///
/// The values are the design file's own, not approximations of a render. See
/// docs/design-system.md for the full table and for the four places this
/// deliberately differs.
enum GlowPalette {
    // MARK: - The two colours

    /// sRGB components, shared by the SwiftUI colour and the Core Image render
    /// so the solid shape and the HDR shape are the same colour.
    ///
    /// Pure white. It was a slightly blue-ish white for a long while, on the
    /// reasoning that light sources read as cool — the design file is #FFFFFF
    /// throughout, and matching it is worth more than the theory.
    static let components: (red: CGFloat, green: CGFloat, blue: CGFloat) = (1.0, 1.0, 1.0)

    static let color = Color(
        .sRGB,
        red: components.red,
        green: components.green,
        blue: components.blue,
        opacity: 1
    )

    /// #8D8D93. Everything that is not lit, at one opacity or another.
    static let grey = Color(.sRGB, red: 141 / 255, green: 141 / 255, blue: 147 / 255, opacity: 1)

    // MARK: - The grey, by weight
    //
    // Four steps, and each one is a different kind of "not now".

    /// A habit already handled today.
    ///
    /// Asked for as "between the ✕ and the label as it was". The ✕ composites to
    /// rgb(70, 70, 74) on black and the label was rgb(199, 199, 204), putting the
    /// midpoint at #87878B — and the grey above is #8D8D93, 4.7% off it. So this
    /// is the grey at full strength, which lands where the eye asked and costs
    /// the palette nothing: no bespoke value, just the one grey again.
    ///
    /// It was briefly lifted well above this on the grounds that SDR reads dark
    /// beside HDR. That is still true, and it stopped mattering once the glows
    /// went to pure white with a single halo pass instead of three.
    static let labelResting = grey

    /// A weekday letter that is not today.
    static let headerRest = grey.opacity(0.6)
    /// A day that went unlogged.
    static let missed = grey.opacity(0.5)
    /// A day still to come. Dark enough to be a socket rather than a mark, which
    /// is what keeps a nearly-empty row legible as a week.
    static let upcoming = grey.opacity(0.16)

    // MARK: - Glow reach
    //
    // Blur radii in points, converted from the design's CSS-style shadows: a CSS
    // blur is roughly twice a SwiftUI shadow radius, so these are half the
    // published number at 1x.

    /// The halo around a mark, as a multiple of slot height.
    /// 18px blur on a 35px slot at 2x.
    static let haloRadius: CGFloat = (18.0 / 2) / 35.0

    /// The ring's halo is softer and offset, and it is drawn at half strength.
    static let ringHaloRadius: CGFloat = (10.0 / 2) / 35.0
    static let ringHaloOpacity: Double = 0.5

    /// Halo reach for glowing text, in points. Tighter than a mark's and not
    /// proportional to it: a glyph is thin, and a mark's halo turns a word into
    /// a smear. 3px and 4px blur at 2x.
    static let labelHalo: CGFloat = 3.0 / 2 / 2
    static let headerHalo: CGFloat = 4.0 / 2 / 2

    // MARK: - Type
    //
    // One family, one weight. The design uses SF Pro Regular at 24px on a 2x
    // widget — 12pt — for the habit name and for every weekday letter, and
    // nothing anywhere is bold. A label that is due is white with a glow, not
    // heavier; the weight never changes, so the row does not reflow when a habit
    // is completed.

    /// The widget's text size, matching the design exactly.
    static let widgetTextSize: CGFloat = 12

    // MARK: - Outside the grid

    /// Amber, and the only colour in the app that is not white or grey. Used for
    /// exactly one thing: saying that the glow is unavailable. A warning in the
    /// app's own white would be indistinguishable from the thing it warns about.
    static let warning = Color(.sRGB, red: 1.0, green: 0.72, blue: 0.22, opacity: 1)
}
