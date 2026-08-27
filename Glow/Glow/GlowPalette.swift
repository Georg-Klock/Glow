import SwiftUI
import WidgetKit

/// Every colour and every effect in the grid.
///
/// **Two colours, both opaque.** White is anything lit; `#8D8D8D` is everything
/// else. There is no third, and there is no scale between them — a slot is
/// identified by whether there is light in it and by its silhouette, never by
/// how far down a grey ramp it sits (#111).
///
/// It used to sit on a ramp: one grey at 55.3% white, which composites to 141
/// on black, and two more stacked on top of it at 71 and 23. Four names, three
/// steps, for a distinction the app does not make. The grid, and the widgets
/// most of all, read as a grey scale when the whole premise is that brightness
/// means one thing.
///
/// #111 collapsed that ramp onto the socket's own value, `#171717`, and #194
/// and #240 each nudged it brighter while holding to one rule: the default grey
/// stays *findable*, never *legible* — that was `greyIncreasedContrast`'s job,
/// behind a setting, so the reading "what stays dark is what never happened"
/// held for everyone who had not asked otherwise. **That rule is retired**
/// (2026-08-24): the default is now `#8D8D8D`, the same value
/// `greyIncreasedContrast` already was — not a fourth nudge, a decision that
/// the two tiers should read the same. See the full reasoning where
/// `greyOpaque` is declared.
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

    /// Everything that is not lit: the resting habit name, the weekday letter
    /// that is not today, the ✕ on a day that went unlogged, the rest day's cut,
    /// and the socket on a day still to come. One name, because they are one
    /// colour — five names for one value would only be a record of what they
    /// used to differ by.
    ///
    /// **A style rather than a `Color`, and that is the whole of the accented
    /// problem.** `resolve(in:)` reads the environment the mark is drawn in, so
    /// the one name answers three questions in one place. What the app draws is
    /// `greyOpaque`; see `GlowGrey`.
    static let grey = GlowGrey()

    /// The second colour, as declared. `#8D8D8D`, opaque.
    ///
    /// **The guardrail this used to respect was retired on purpose, not
    /// exceeded by accident** (2026-08-24). Three nudges — #111's `#171717`,
    /// #194's `#242424`, #240's `#2B2B2B` — all held one rule: stay under 1.5:1
    /// on black, unmistakably not-lit, because legible body text was
    /// `greyIncreasedContrast`'s job behind a setting, not the default's. #240
    /// said explicitly that the next report of "still unreadable" would be
    /// asking to move that rule rather than nudge inside it, and that is what
    /// this is: judged against a reference screenshot of ordinary dark-mode
    /// body text, not a fourth guess.
    ///
    /// **The value is `greyIncreasedContrast`'s, not a new one.** Rather than
    /// pick a fresh point on the scale, this asks the same question #111 asked
    /// when it first collapsed the ramp: is there already a number in this file
    /// that means what is wanted here? There was — the app's own pre-#111 grey,
    /// already measured at 6.3:1, comfortably clearing the 4.5:1 body text
    /// asks for. So the default and Increase Contrast now read the same, and
    /// the two-tier model — dark by default, legible on request — is gone.
    /// `Tests/WidgetBackgroundTests.swift` asserts the equality directly, so a
    /// future edit to one without the other fails loudly rather than drifting.
    static let greyOpaque = greyIncreasedContrast

    /// The grey Increase Contrast asks for — and, since 2026-08-24, the grey
    /// everyone gets.
    ///
    /// Kept under its own name for what it used to be the answer to: for #111
    /// through #240, the default grey stayed deliberately dim — "what stays
    /// dark is what never happened," carried through to type — and this was
    /// the honouring of the setting for people who found that too dim to read.
    /// That distinction is what retired; the number did not need to.
    ///
    /// `#8D8D8D` is not a number invented for this: it is what `grey` composited
    /// to before #111, so Increase Contrast gets the app's own previous grey.
    /// It measures 6.3:1 on black, comfortably past the 4.5:1 asked of body text.
    ///
    /// **`greyOpaque` now equals this exactly** (2026-08-24) — declared as its
    /// own named constant still, because the setting and the default answer
    /// different questions even on the day their values happen to agree, and a
    /// future change to one is not implicitly a change to both.
    static let greyIncreasedContrast = Color(
        .sRGB, red: 141 / 255, green: 141 / 255, blue: 141 / 255, opacity: 1
    )

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
    /// Not `greyOpaque`, and the reason is measured. #124 gave the Settings
    /// toggles an explicit tint because white is what this app reserves for lit
    /// and a switch track is not lit; the ON track landed at 181,181,183 against
    /// an untouched system OFF track at 90,90,94. `greyOpaque` at 141 no longer
    /// falls *below* the OFF track the way `#171717` and `#2B2B2B` did — the
    /// 2026-08-24 move to `#8D8D8D` happens to clear it — but 141 is still well
    /// short of the ON track's measured 181, so borrowing it would still be a
    /// visibly dimmer switch than the one that was actually measured, not the
    /// inverted one earlier values risked.
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
        return GlowPalette.greyOpaque
    }
}
