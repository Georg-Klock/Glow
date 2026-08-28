import SwiftUI
import WidgetKit

/// Every colour and every effect in the grid.
///
/// **One hex at three steps, and white above them** (#335, 2026-08-28). Light
/// has two tiers (#334): `#FFFFFF` with an HDR halo *emits*, and everything
/// below it reflects. The reflecting tier is `#D9D9D9`, at two strengths —
/// full for what is done or handled, half for what is at rest.
///
/// | | |
/// | --- | --- |
/// | `#FFFFFF` + halo | emitting: still actionable |
/// | `#D9D9D9` @ 100% | lit, not emitting: a completion, today handled |
/// | `#D9D9D9` @ 50% | at rest: the rest of the week |
///
/// **This is not the grey ramp #111 collapsed.** That ramp was four names for
/// one distinction, stacking opacities until the grid read as a grey scale
/// while the whole premise was that brightness means one thing. These three are
/// three different claims — *do this now*, *this happened*, *nothing is asked
/// here* — and the middle one only exists because #334 gave light a ceiling a
/// completion does not reach.
///
/// It used to sit on a ramp: one grey at 55.3% white, which composites to 141
/// on black, and two more stacked on top of it at 71 and 23. Four names, three
/// steps, for a distinction the app does not make. The grid, and the widgets
/// most of all, read as a grey scale when the whole premise is that brightness
/// means one thing.
///
/// #111 collapsed that ramp onto the socket's own value, `#171717`, and #194
/// and #240 each nudged it brighter while holding to one rule: the default grey
/// stays *findable*, never *legible*. 2026-08-24 retired that rule and moved
/// the default to `#8D8D8D`, the value Increase Contrast already used, so the
/// two read the same. **2026-08-28 moves again**, and it is worth being exact
/// about what it does and does not reopen — see where `greyResting` is
/// declared.
///
/// **Two values below still carry alpha, and neither is a colour the app
/// draws.** `greyAccented` is what the system is handed once it has already
/// discarded the colours, and `controlTint` is a system switch's track. Both
/// are documented where they are declared.
///
/// **This file is the source of truth for colour.** There is no design-system
/// document to reconcile it against any more: the numbers below, and the
/// derivations in `GlowShape`, `WidgetMetrics` and `SlotLayout`, are what the
/// app draws. Where a value departs from the design file it says so in place.
///
/// One cleanup worth doing when something else touches this file: `haloRadius`
/// and `ringHaloRadius` differ only because the file draws the ring's halo
/// softer. If the ring keeps its offset pair anyway, one radius would do.
///
/// Reading a radius here does not tell you what lands on screen: every drop
/// shadow is multiplied by `GlowSettings.haloScale(peak)` — 0.2 at the shipping
/// default of 2x, `maxHaloScale` at the top of the range. The ring's inner pair
/// are the exception — they are baked into the stroke in `GlowImageView` and
/// are not scaled.
enum GlowPalette {
    // MARK: - The colours

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

    /// Everything at rest: the resting habit name, the weekday letter that is
    /// not today, the ✕ on a day that went unlogged, the rest day's cut, and
    /// the socket on a day still to come. One name, because they are one claim
    /// — nothing is asked here.
    ///
    /// **A style rather than a `Color`, and that is the whole of the accented
    /// problem.** `resolve(in:)` reads the environment the mark is drawn in, so
    /// the one name answers three questions in one place. What the app draws is
    /// `greyResting`; see `GlowGrey`.
    static let grey = GlowGrey()

    /// **`#D9D9D9` at 50%** — the resting step, and what the app draws by
    /// default (#335, 2026-08-28).
    ///
    /// It composites to 108.5 on black, **4.0:1**. The value it replaces,
    /// `#8D8D8D`, was 6.3:1, so this is a step *down* in contrast and that is
    /// the part worth being careful about — 2026-08-24 moved the default up to
    /// exactly that value because the grey had been reported unreadable, and
    /// retired the two-tier "dim by default, legible on request" model to do
    /// it.
    ///
    /// **What makes that not a reversal is that there are three steps now, not
    /// two.** 2026-08-24's problem was a single resting grey that had to carry
    /// everything and was too dim to read. Here the resting step is genuinely
    /// the dimmest of three: `color` emits, `lit` is a full-strength `#D9D9D9`
    /// at 14.9:1 for what is done or handled, and this is what is left over.
    /// A reader is not being asked to read the app at 4:1 — they are being
    /// asked to read *the part of it that is asking nothing* at 4:1, with
    /// everything live above it.
    ///
    /// **And the setting still answers.** `greyIncreasedContrast` is `lit`, so
    /// anyone who found the old grey hard to read gets 14.9:1 rather than the
    /// 6.3:1 they used to get. The tier that retired was *dim by default,
    /// legible on request*; what is here is *quiet by default, loud on
    /// request*, and the loud end is brighter than anything this palette has
    /// offered before.
    ///
    /// Translucent rather than a flat `#6D6D6D`, because the design draws it as
    /// one hex at two strengths and because the alpha is what accented
    /// rendering can still see — see `greyAccented`.
    static let greyResting = lit.opacity(restingAlpha)

    /// How far down the resting step sits. Half, from the design file.
    static let restingAlpha: Double = 0.5

    /// **`#D9D9D9` at full strength** — lit, but not emitting (#334).
    ///
    /// A completion, today's weekday letter once everything is closed, the name
    /// of a habit already handled today. The second tier of light: an object
    /// catching it rather than a source of it, which is why it is not `color`.
    ///
    /// 14.9:1 on black, so it is also what Increase Contrast resolves to.
    static let lit = Color(
        .sRGB, red: 217 / 255, green: 217 / 255, blue: 217 / 255, opacity: 1
    )

    /// The grey Increase Contrast asks for: the `lit` step, at full strength.
    ///
    /// **The setting's job came back, with a better answer than it ever had**
    /// (#335). For #111 through #240 this was the escape hatch from a
    /// deliberately dim default, at `#8D8D8D` and 6.3:1. 2026-08-24 collapsed
    /// it into the default, because a setting whose whole argument is "the
    /// default should have been this bright" is an argument for changing the
    /// default. #335 gives the resting step a *reason* to be dim — it is one of
    /// three, and the two above it carry everything live — so the escape hatch
    /// is worth having again, and it now lands on 14.9:1 rather than 6.3:1.
    ///
    /// Declared as its own name rather than used inline, because the setting
    /// and the `lit` step answer different questions even while they share a
    /// value, and a future change to one is not implicitly a change to both.
    static let greyIncreasedContrast = lit

    /// The grey under *accented* rendering, which is what a Home Screen set to
    /// Clear or Tinted puts a widget into.
    ///
    /// There the system tints every pixel a single white and keeps only the
    /// alpha. An opaque grey has no alpha to be read: it comes out identical to
    /// a lit mark, and the entire hierarchy collapses into one tone. So in that
    /// mode, and only in that mode, the grey is stored as alpha instead — the
    /// value the whole palette used to be built from.
    ///
    /// **This is not a third colour.** It is the same one grey, expressed in the
    /// only quantity the system has not thrown away. #53 would remove the mode
    /// entirely with `containerBackgroundRemovable(false)`; until it does, or if
    /// it never does, this is what keeps a Tinted Home Screen readable.
    static let greyAccented = Color.white.opacity(greyAlpha)

    /// The alpha the grey used to be stored at, and the one number that outlived
    /// the ramp. Two places still need a grey expressed as alpha rather than as
    /// a colour, and both are places the app is not the one painting.
    static let greyAlpha: Double = 0.553

    /// A system switch's ON track.
    ///
    /// Not a grid colour, and the reason is measured. #124 gave the Settings
    /// toggles an explicit tint because white is what this app reserves for lit
    /// and a switch track is not lit; the ON track landed at 181,181,183 against
    /// an untouched system OFF track at 90,90,94. The resting grey composites
    /// to 108 and would fall *below* the OFF track, which is the inversion
    /// #124 was fixing; `lit` at 217 overshoots the measured 181 the other way.
    /// Neither is the number that was measured, so the switch keeps its own.
    ///
    /// A `Toggle` in a `Form` is one of iOS's own components on a support
    /// screen, which is the boundary #111 draws its own scope at. So it keeps
    /// the value that measured, declared here under its own name rather than
    /// borrowed from a grid colour it is no longer allowed to share.
    static let controlTint = Color.white.opacity(greyAlpha)

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
    // multiplies every drop shadow by `GlowSettings.haloScale(peak)` — 0.2 at
    // the shipping default of 2x, so the dot's halo renders at 1.8 on a 17.455
    // slot, not 9, and reaches 12.6 at the top of the range.
    // `ringInnerRadius` is the exception: it is an inner shadow inside the
    // stroke and the setting never touches it.

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

    // No `ringWash`. The design file gave the open ring a 1% white fill and this
    // type carried the token for it, declared and never applied through every
    // release so far — `GlowImageView` draws the ring with `strokeBorder`, which
    // paints a border and no fill. Deleted rather than wired up (#65): the
    // document that specified it no longer exists, the ring's interior is
    // deliberately clear, and a 1% white is the wrong sign for the only problem
    // that interior actually has — halo bleed from the neighbouring segments
    // making it read grey, whose fix is black beneath the glow, not white
    // inside it. See docs/decisions.md.

    /// Halo reach for glowing text, in points. Tighter than a mark's and not
    /// proportional to it: a glyph is thin, and a mark's halo turns a word into
    /// a smear.
    ///
    /// **These two divide twice and the marks above divide not at all, and that
    /// is correct** (#63). The difference is what kind of number the file was
    /// read for, not an inconsistency:
    ///
    ///  - `haloRadius` and the ring's radii are *Figma shadow radii*, taken
    ///    straight. A Figma radius is about a SwiftUI radius, so nothing is
    ///    divided.
    ///  - These two are *CSS blurs at 2x* — 3px and 4px. Halve for 1x, halve
    ///    again because a CSS blur is about twice a Figma radius, and 0.75 and
    ///    1.0 are the radii that fall out.
    ///
    /// Worth spelling out because the project has already paid for the opposite
    /// slip once, halving numbers that were already halved and landing every
    /// glow at a quarter of its reach. The check that separates the two cases is
    /// whether the source number was a blur or a radius, and there is no way to
    /// tell them apart from the value alone.
    ///
    /// A design document used to publish 1.5 and 2 for these rows, which is the
    /// 1x CSS blur rather than the radius — the same column quoting two
    /// different quantities. That document is gone (see docs/decisions.md, "The
    /// code is the source of truth for design"), and these two lines are now the
    /// only statement of the number.
    ///
    /// What would reopen it: 0.75pt against 1.5pt of blur on 12pt text is not a
    /// difference the simulator can show, because it has no EDR headroom and the
    /// halo is the part that needs it. If a due label ever reads under-lit on a
    /// device, the thing to suspect is that the file's number was a radius after
    /// all and one of these divisions is spurious.
    ///
    /// **Looked at, and it does not** (#101, claim 5). iPhone 14 Pro, iOS
    /// 26.5.2, 2026-08-25, with `glowPeakHeadroom` at 12, the shipping default
    /// that day — a due habit's name beside its own due mark, the label's halo
    /// at 0.75pt against the mark's rendered 15.26pt. Georg: the name reads
    /// lit.
    ///
    /// That is the observation this comment asked for, and it is worth being
    /// exact about what it settles. It does **not** prove 0.75 is the number
    /// the design file meant; nothing short of the file itself could. It closes
    /// the specific failure named above — a label that reads under-lit next to
    /// its mark, which is what a spurious division would produce and what four
    /// halved-twice glows looked like the last time this trap was sprung. The
    /// arithmetic in #63 and the device now agree, which is as much as this
    /// number can be asked to carry.
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

/// `GlowPalette.grey`, resolved against the environment it is drawn in.
///
/// A `ShapeStyle` rather than a `Color` because two of the three answers are not
/// the app's to choose: whether the reader asked for **Increase Contrast**, and
/// whether the system is about to discard every colour on the way to a Tinted
/// Home Screen. A `Color` is a value and cannot ask; a style is resolved at draw
/// time and is handed the whole environment.
///
/// Put another way: **the palette holds one grey, and this is where its three
/// expressions live** — the colour the app draws, the colour it draws instead
/// when asked for more contrast, and the alpha it hands the system when the
/// system has stopped taking colours.
///
/// Precedence is deliberate. Accented rendering wins over Increase Contrast:
/// under accented there is no such thing as a light or a dark grey, only a more
/// or less transparent one, so lifting the value there would say nothing.
struct GlowGrey: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.widgetRenderingMode == .accented {
            return GlowPalette.greyAccented
        }
        if environment.colorSchemeContrast == .increased {
            return GlowPalette.greyIncreasedContrast
        }
        return GlowPalette.greyResting
    }
}
