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
/// **This file is the source of truth for colour.** There is no design-system
/// document to reconcile it against any more: the numbers below, and the
/// derivations in `GlowShape`, `WidgetMetrics` and `SlotLayout`, are what the
/// app draws. Where a value departs from the design file it says so in place.
///
/// Two cleanups worth doing when something else touches this file:
///
///  - `headerRest` and `labelResting` are the same value and could be one name.
///  - `haloRadius` and `ringHaloRadius` differ only because the file draws the
///    ring's halo softer. If the ring keeps its offset pair anyway, one radius
///    would do.
///
/// Reading a radius here does not tell you what lands on screen: every drop
/// shadow is multiplied by `GlowSettings.haloScale(peak)`, which is 1.7 at the
/// shipping default of 12x. The ring's inner pair are the exception — they are
/// baked into the stroke in `GlowImageView` and are not scaled.
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

    /// Everything that is not lit.
    ///
    /// **White at 55%, not the design's solid #8D8D93** — and the difference is
    /// invisible here but load-bearing in the widget. On black the two are the
    /// same colour to within six levels of blue out of 255.
    ///
    /// What they are not the same at is *accented* rendering, which is what a
    /// Home Screen set to Clear or Tinted puts a widget into. There the system
    /// tints content a single white and keeps only the alpha. A solid grey comes
    /// out identical to a lit mark and the entire hierarchy collapses into one
    /// tone; white at 55% stays 55% and the grid still reads.
    ///
    /// So the alpha is the thing being stored, and the colour is incidental.
    static let grey = Color.white.opacity(0.553)

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
    ///
    /// The same grey at the same strength as a resting habit name. It was 60%
    /// here, taken from generated CSS that had folded a node opacity into the
    /// colour; the file's own paint is 100%, and a census of all 89 paints in
    /// the frame turned up no 60% anywhere.
    static let headerRest = grey
    /// A day that went unlogged.
    static let missed = grey.opacity(0.5)
    /// The rest day's cut: the line down its column. It marks absence, and
    /// absence does not glow — the missed cross's grey, turned vertical.
    static let restCut = missed
    /// A day still to come. Dark enough to be a socket rather than a mark, which
    /// is what keeps a nearly-empty row legible as a week.
    static let upcoming = grey.opacity(0.16)

    // MARK: - Glow reach
    //
    // These are the design file's own shadow radii, not halved. The generated
    // CSS doubles every one of them, and halving those already-doubled numbers
    // — which this used to do — landed every glow at a quarter of its reach.
    // The rule that avoids it: a Figma shadow radius is about half a CSS blur,
    // and about the same number as a SwiftUI `.shadow(radius:)`.
    //
    // "About the same number" is as far as it goes, and it was measured rather
    // than assumed: rendering the same ring at the same radius in both, Figma's
    // halo reaches 0.75x as far as SwiftUI's at half its edge brightness, and
    // the kernels differ in shape — Figma is brighter near the source with a
    // shorter tail. Matching a glow by eye in Figma will under-reach the app.
    //
    // What lands on screen is also not the number below. `GlowModifier`
    // multiplies every drop shadow by `GlowSettings.haloScale(peak)`, which is
    // 1.7 at the shipping default of 12x — so the dot's halo renders at 15.26
    // on a 17.455 slot, not 9. `ringInnerRadius` is the exception: it is an
    // inner shadow inside the stroke and the setting never touches it.

    /// The halo around a completion, as a multiple of slot height. 9 on 17.5.
    static let haloRadius: CGFloat = 9.0 / 17.5

    /// The ring's halo: wider than the stroke suggests, offset above and below,
    /// and drawn at half strength. 5 on 17.5, offset 1.25.
    static let ringHaloRadius: CGFloat = 5.0 / 17.5
    static let ringHaloOffset: CGFloat = 1.25 / 17.5
    /// The offset as a fraction of the halo's own radius: 1.25 of 5.
    static let ringHaloOffsetRatio: CGFloat = 1.25 / 5.0
    static let ringHaloOpacity: Double = 0.5

    /// The ring's inner pair, which thickens the stroke's apparent brightness at
    /// top and bottom. 2.5 on 17.5, same offset.
    static let ringInnerRadius: CGFloat = 2.5 / 17.5

    /// A 1% white wash inside the ring. Almost nothing, and the file is explicit
    /// about it being non-zero.
    static let ringWash = Color.white.opacity(0.01)

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

    /// The widget's background under Default appearance: true black, declared
    /// explicitly rather than as `Color.black`, which is a system colour and
    /// free to be something other than 0,0,0.
    ///
    /// Under Tinted or Clear this is removed and replaced with glass, so it is
    /// only ever what Default sees.
    static let widgetBackground = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)

    /// Amber, and the only colour in the app that is not white or grey. Used for
    /// exactly one thing: saying that the glow is unavailable. A warning in the
    /// app's own white would be indistinguishable from the thing it warns about.
    static let warning = Color(.sRGB, red: 1.0, green: 0.72, blue: 0.22, opacity: 1)
}
