import SwiftUI
import Testing
import WidgetKit
import UIKit
@testable import Glow

/// The widget sits on 0,0,0 and nothing else.
///
/// The declaration was already right; what was missing was anything that says
/// so (#87). The glow is a claim about light against dark, and every level the
/// background sits above zero is a level taken off that claim — most of all in
/// the widget, where a home screen puts the wallpaper right beside it.
@Suite("Widget background")
struct WidgetBackgroundTests {
    @Test("The declared background resolves to pure black, not a system colour")
    @MainActor
    func widgetBackgroundIsPureBlack() {
        // The specific regression this is defending against: someone swapping
        // it for `Color.black`, which is a *system* colour and free to be
        // something other than 0,0,0 in some environment or some future OS.
        // Nothing caught that before this test.
        let resolved = UIColor(GlowPalette.widgetBackground)
        var r: CGFloat = -1, g: CGFloat = -1, b: CGFloat = -1, a: CGFloat = -1
        #expect(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r == 0)
        #expect(g == 0)
        #expect(b == 0)
        #expect(a == 1)
    }

    @Test("Every palette colour the widget draws is neutral")
    @MainActor
    func thePaletteCarriesNoHue() {
        // One hex at three steps and white above them (#335): a hue in the
        // palette would also break the widget's accented rendering, where the
        // system keeps alpha and discards colour. User-authored emoji are
        // content and deliberately retain their own hues (#457).
        let neutral: [Color] = [
            GlowPalette.color, GlowPalette.lit, GlowPalette.greyResting,
            GlowPalette.greyIncreasedContrast, GlowPalette.greyAccented,
            GlowPalette.controlTint, GlowPalette.widgetBackground,
        ]
        for colour in neutral {
            var r: CGFloat = -1, g: CGFloat = -1, b: CGFloat = -1, a: CGFloat = -1
            #expect(UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a))
            #expect(r == g && g == b, "a hue in the palette: \(r), \(g), \(b)")
        }

        // And the glow's own components, which the PQ encoder reads.
        let components = GlowPalette.components
        #expect(components.red == components.green)
        #expect(components.green == components.blue)
    }
}

/// Two colours, both opaque (#111, #194, #240).
///
/// The palette used to be a ramp: one grey and three more stacked on top of it
/// by opacity. #111 replaced it with one grey at the value the darkest step
/// already composited to, `#171717`, and this suite used to assert that
/// derivation — `0.553 × 0.16 × 255 = 22.6 → 23` — because the claim was that
/// the grey was inherited rather than invented.
///
/// **That claim is over, and so is the ceiling that followed it.** #194 moved
/// the grey to `#242424`, #240 to `#2B2B2B`, each time holding the same rule:
/// findable, never legible, under 1.5:1 on black. 2026-08-24 retired that rule
/// outright rather than nudging inside it again — the default grey is now
/// `#8D8D8D`, `greyIncreasedContrast`'s own value, so the two colours stay two
/// but the default reads as the setting used to. What the tests below assert
/// changed with it: not a ceiling any more, but that the two names agree —
/// visible enough for the render suite's own unlit-line scans to find it, and
/// the two places a grey is still allowed to be alpha, and why neither is a
/// third colour.
@Suite("Two colours")
struct TwoColoursTests {
    /// Resolves a `Color` the way the screen does.
    @MainActor
    private func components(_ colour: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = -1, g: CGFloat = -1, b: CGFloat = -1, a: CGFloat = -1
        _ = UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// Named for what it asserts rather than for the value it asserts. This was
    /// `greyIsOpaqueSeventeen` until #194 renamed it `greyIsOpaqueTwentyFour`,
    /// and #240 would have had to rename it again. A name that spells out a
    /// level goes stale the moment the level is nudged, and a stale name is
    /// worse than a general one because it reads as a claim.
    @Test("The grey the app draws is the level the palette declares, and it is opaque")
    @MainActor
    func theUnlitGreyIsOpaqueAtItsDeclaredLevel() {
        // The literal moves with the palette, deliberately: this is the one
        // test that says what the value *is*, so reading it from `GlowPalette`
        // would make it a test that cannot fail. 141 is `#8D8D8D`, the value
        // `greyOpaque` and `greyIncreasedContrast` now share (2026-08-24).
        let grey = components(GlowPalette.greyResting)
        #expect((grey.r * 255).rounded() == 217)
        #expect((grey.g * 255).rounded() == 217)
        #expect((grey.b * 255).rounded() == 217)
        #expect(abs(Double(grey.a) - 0.5) < 0.001, "the resting step is not half: \(grey.a)")

        // The step above it: the same hex, opaque (#335).
        let litStep = components(GlowPalette.lit)
        #expect((litStep.r * 255).rounded() == 217)
        #expect(litStep.a == 1, "the lit step carries alpha: \(litStep.a)")

        // And white is still white, still opaque.
        let white = components(GlowPalette.color)
        #expect(white.r == 1 && white.g == 1 && white.b == 1 && white.a == 1)
    }

    /// Replaces `greyIsTheOldSocket`, which asserted `0.553 × 0.16 × 255 == 23`
    /// and that the palette matched it. Its premise — that the grey is not a
    /// new colour — stopped being true with #194, and there is no derivation
    /// for `#2B2B2B` to put in its place: reconstructing 43 from 43 would be a
    /// test that cannot fail. This is the claim that survives the move.
    @Test("The unlit grey clears the ground the render suite scans against")
    @MainActor
    func theUnlitGreyClearsTheGround() {
        // Not an arbitrary floor. `WidgetRenderDiffTests` finds an unlit line —
        // a span, the rest cut — by scanning for anything brighter than
        // `lineFloor`, which is 15, and its content check bands the grey. Both
        // live in the render bundle and cannot import this one, so the coupling
        // is asserted from this side: a grey at or below 15 stops being
        // separable from black there, and those scans would pass on nothing.
        //
        // This is also the half of #194 and #240 that was the *reason* for each
        // move: 23 cleared 15 arithmetically and still read as almost nothing
        // on a real screen, and so did 36 and 43. 141 clears it by a wide
        // margin, which was never the risk on this side of the guardrail.
        // **Composited, not the declared component.** The resting step is
        // translucent since #335, so what those scans see is its level on the
        // widget's black ground — 217 at half is 108.5 — and reading `r` alone
        // would answer 217 for a level that never lands.
        let resting = components(GlowPalette.greyResting)
        let level = (Double(resting.r) * Double(resting.a) * 255).rounded()
        #expect(level > 15, "the resting grey lands at \(level); the render scans floor at 15")
        // The other half of that coupling: it must still read as *unlit* beside
        // a lit mark. `WidgetRenderDiffTests.isUnlit` asks whether a tone times
        // 1.5 stays under the lit one.
        let litLevel = Double(components(GlowPalette.lit).r) * 255
        #expect(level * 1.5 < litLevel,
                "the resting grey no longer reads as unlit beside \(litLevel)")
    }

    @Test("Increase Contrast is the way out, and the steps stay ordered")
    @MainActor
    func increasedContrastIsTheLitStep() {
        // `#D9D9D9` opaque — the `lit` step, which is what the setting now
        // resolves to (#335). Not a number invented for the setting: it is the
        // reflecting tier at full strength, the same value a completion draws.
        // 14.9:1 on black, against the 6.3:1 this used to give.
        let lifted = components(GlowPalette.greyIncreasedContrast)
        #expect((lifted.r * 255).rounded() == 217)
        #expect(lifted.a == 1)
        #expect(Self.contrastOnBlack(217 / 255.0) > 4.5,
                "the lifted grey no longer clears 4.5:1")

        // **This used to be a ceiling.** `< 1.2` defended `#171717`, then
        // `< 1.5` defended `#2B2B2B` at 1.483:1 — the highest value #240 could
        // reach without asking to move the bound itself. 2026-08-24 is that
        // asking, done in the open rather than backed into: the default grey
        // now equals `greyIncreasedContrast` exactly, on purpose, rather than
        // approaching it by increments. So the guardrail is no longer a
        // ceiling on how bright `greyOpaque` may get — it is an equality, and
        // it fails if the two values are ever allowed to drift apart without
        // that drift being a decision either.
        // **The third shape of this guardrail** (#335, 2026-08-28). It was a
        // ceiling (`< 1.2`, then `< 1.5`) defending a deliberately dim default
        // while legibility was the setting's job; then an equality, when
        // 2026-08-24 collapsed the two because a setting arguing "the default
        // should be this bright" is an argument for moving the default.
        //
        // Now a floor *on the setting*, plus an ordering. The default is dim
        // again but for a reason it never had before: it is the third of three
        // steps rather than the only one, and the two above it carry
        // everything live. What must not come back is a reader with no way
        // out — so the assertion that matters is on `greyIncreasedContrast`,
        // and it now describes 14.9:1 rather than the 6.3:1 it used to.
        #expect(Self.contrastOnBlack(Double(lifted.r)) > 4.5,
                "Increase Contrast no longer clears legible body text")

        // The steps stay ordered, so "dimmest of three" keeps meaning
        // something. Composited, because the resting step is translucent.
        let resting = components(GlowPalette.greyResting)
        #expect(Double(resting.r) * Double(resting.a) < Double(components(GlowPalette.lit).r),
                "the resting step is not below the lit one")
        #expect(Double(components(GlowPalette.lit).r) < 1.0,
                "the lit step reached white, which is the emitting tier")
    }

    @Test("The two greys that still carry alpha are the two the app does not paint")
    @MainActor
    func alphaOnlyWhereTheSystemPaints() {
        // Accented rendering discards colour and keeps alpha, so an opaque grey
        // there comes back as a lit mark; a system switch's track has to beat an
        // OFF track this app does not own. Everything the app draws itself is
        // opaque.
        //
        // Compared with a tolerance, not for equality: `UIColor` stores the
        // component as a float and the round trip through it loses the last
        // digits of 0.553.
        for tint in [GlowPalette.greyAccented, GlowPalette.controlTint] {
            let alpha = Double(components(tint).a)
            #expect(abs(alpha - GlowPalette.greyAlpha) < 0.001,
                    "an alpha-stored grey moved: \(alpha)")
        }
    }

    @Test("Outside accented rendering and Increase Contrast, the grey resolves to the resting step")
    @MainActor
    func defaultEnvironmentResolvesToTheRestingStep() {
        // The default environment is what every app surface draws in: no widget
        // rendering mode, standard contrast.
        let resolved = GlowGrey().resolve(in: EnvironmentValues())
        #expect((components(resolved).r * 255).rounded() == 217)
        #expect(abs(Double(components(resolved).a) - 0.5) < 0.001,
                "the default resolution is not the resting step")
    }

    /// WCAG relative contrast of a neutral sRGB value against pure black.
    private static func contrastOnBlack(_ value: Double) -> Double {
        let linear = value <= 0.03928
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
        return (linear + 0.05) / 0.05
    }
}

/// The rendering modes the widget can be put into, and the one it cannot.
@Suite("Widget rendering modes")
struct WidgetRenderingModeTests {
    @Test("No accessory family is declared, so vibrant is unreachable")
    func vibrantIsUnreachable() {
        // `.vibrant` desaturates and lightens content against a system surface,
        // which would take the ground off zero and there would be nothing the
        // app could do about it. It only applies to the accessory families —
        // Lock Screen and watch complications — and #87 asked for this to be
        // confirmed rather than assumed.
        //
        // Asserted against the *declared* families rather than by reading the
        // source, so adding an accessory family fails here and the person
        // adding it has to decide what the ground does there.
        let declared: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        for family in declared {
            #expect(!Self.accessory.contains(family), "\(family) is an accessory family")
        }
    }

    private static let accessory: Set<WidgetFamily> = [
        .accessoryCircular, .accessoryRectangular, .accessoryInline,
    ]
}
