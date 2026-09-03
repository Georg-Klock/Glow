import SwiftUI
import WidgetKit

/// Every colour and every effect in the grid.
///
/// **One hex at three steps, and white above them** (#335, 2026-08-28). Light
/// has two tiers (#334): `#FFFFFF` with the HDR tile over it *emits*, and
/// everything below it reflects. The reflecting tier is `#D9D9D9`, at two strengths —
/// full for what is done or handled, half for what is at rest.
///
/// | | |
/// | --- | --- |
/// | `#FFFFFF` + HDR tile | emitting: still actionable |
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
    // **There is none any more.** A lit mark used to cast an SDR drop shadow —
    // the halo — and this section held its radii: one for a completion, three
    // for the ring's offset pair, and two more for glowing text. All of them
    // are gone with the halo itself (#394), along with the ring's unused inner
    // radius that was documented as their exception. `GlowModifier` now draws
    // the HDR tile masked to the silhouette and nothing else, so a mark is lit
    // exactly as far as its own shape reaches.
    //
    // The rule the section existed to protect is still worth keeping if a
    // reach ever comes back: a Figma shadow radius is about half a CSS blur
    // and about the same number as a SwiftUI `.shadow(radius:)`. Halving an
    // already-doubled CSS number is what once landed every glow at a quarter
    // of its reach, and the value alone does not say which kind it is. See
    // #63 and docs/decisions.md.

    // No `ringWash`. The design file gave the open ring a 1% white fill and this
    // type carried the token for it, declared and never applied through every
    // release so far — `GlowImageView` draws the ring with `strokeBorder`, which
    // paints a border and no fill. Deleted rather than wired up (#65): the
    // document that specified it no longer exists, the ring's interior is
    // deliberately clear, and a 1% white was the wrong sign for the only problem
    // that interior actually had — light bleeding in from the neighbouring
    // segments and making it read grey, whose fix is black beneath the glow, not
    // white inside it. See docs/decisions.md.

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

    /// The ground the widget's surface resolves against: true black, declared
    /// explicitly rather than as `Color.black`, which is a system colour and
    /// free to be something other than 0,0,0.
    ///
    /// Under Default appearance the container background is composited into the
    /// snapshot opaquely and every alpha lands on this. Under Tinted or Clear
    /// the system drops it and substitutes its own glass.
    static let widgetBackground = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)

    /// **The widget's surface: dark glass over black** (#333).
    ///
    /// `WidgetMetrics` used to end with a note explaining why there were no
    /// background constants — the design drew a gradient container, the widget
    /// followed it for a while, and on a real Home Screen it read as a panel
    /// sitting on the wallpaper rather than marks floating on it. **That
    /// measurement was real and this is a decision on top of it, not a finding
    /// that it was wrong.** What changed is what the marks are: sockets pressed
    /// into a surface (#332) need a surface to be pressed into, and a panel is
    /// the point rather than the problem.
    ///
    /// `.ultraThinMaterial` is the spelling available at the 18.0 deployment
    /// target — Liquid Glass is iOS 26 and out of reach. The design draws the
    /// fill as `#FFFFFF 10% → 7%`, which is Figma's stand-in for a material
    /// rather than the value to type in.
    ///
    /// Declared here as one view so the widget and the render harness cannot
    /// disagree about what the surface is: a baseline rendered over a different
    /// ground than the widget ships is a baseline of nothing.
    @ViewBuilder
    static func widgetSurface(reduceTransparency: Bool) -> some View {
        ZStack {
            widgetBackground
            if TransparencyPolicy.drawsMaterial(reduceTransparency: reduceTransparency) {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    /// The symbol section's system bar, with the same opaque fallback as every
    /// other surface carrying text when Reduce Transparency is enabled.
    @ViewBuilder
    static func barSurface(reduceTransparency: Bool) -> some View {
        if TransparencyPolicy.drawsMaterial(reduceTransparency: reduceTransparency) {
            Rectangle().fill(.bar)
        } else {
            widgetBackground
        }
    }

    /// Amber, and the only colour in the app that is not white or grey. It says
    /// that something visible cannot carry the full promise it appears to: the
    /// glow is unavailable, or a typed name will be cut on the compact row. A
    /// warning in the app's own white would be indistinguishable from the thing
    /// it warns about.
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
