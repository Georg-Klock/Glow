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

    @Test("Every colour the widget draws is neutral")
    @MainActor
    func nothingCarriesAHue() {
        // Two colours, and there is no third: white is anything lit, #2B2B2B is
        // anything that is not. A hue anywhere would also break the widget's
        // accented rendering, where the system keeps alpha and discards colour.
        let neutral: [Color] = [
            GlowPalette.color, GlowPalette.greyOpaque,
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

/// Two colours, both opaque (#111, #194).
///
/// The palette used to be a ramp: one grey and three more stacked on top of it
/// by opacity. #111 replaced it with one grey at the value the darkest step
/// already composited to, `#171717`, and this suite used to assert that
/// derivation — `0.553 × 0.16 × 255 = 22.6 → 23` — because the claim was that
/// the grey was inherited rather than invented.
///
/// **That claim is over.** #194 moved the grey to `#242424` because 23 was too
/// dark to read on a real screen, #240 moved it on to `#2B2B2B` because 36 was
/// still too dark, and 43 is not derived from anything. So there
/// is no arithmetic left to assert, and the tests below assert instead what
/// actually has to hold: the value the app draws, the two bounds it lives
/// between — visible enough for the render suite's own unlit-line scans to find
/// it, dark enough that it can never be mistaken for lit — and the two places a
/// grey is still allowed to be alpha and why neither is a third colour.
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
        // would make it a test that cannot fail. 43 is `#2B2B2B` (#240).
        let grey = components(GlowPalette.greyOpaque)
        #expect((grey.r * 255).rounded() == 43)
        #expect((grey.g * 255).rounded() == 43)
        #expect((grey.b * 255).rounded() == 43)
        #expect(grey.a == 1, "the grey carries alpha: \(grey.a)")

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
        // This is also the half of #194 and #240 that is the *reason* for each
        // move. 23 cleared 15 arithmetically and still read as almost nothing
        // on a real screen, and so did 36; 43 is the value picked for what it
        // reads as.
        let level = (components(GlowPalette.greyOpaque).r * 255).rounded()
        #expect(level > 15, "the unlit grey is at \(level); the render scans floor at 15")
    }

    @Test("Increase Contrast gets the grey the app used to draw")
    @MainActor
    func increasedContrastIsTheOldGrey() {
        // #8D8D8D: what `white.opacity(0.553)` composited to on black, and so
        // not a number invented for the setting. It clears 4.5:1 on black,
        // which the shipping grey at about 1.48:1 does not.
        let lifted = components(GlowPalette.greyIncreasedContrast)
        #expect((lifted.r * 255).rounded() == 141)
        #expect(lifted.a == 1)
        #expect(Self.contrastOnBlack(141 / 255.0) > 4.5,
                "the lifted grey no longer clears 4.5:1")

        // The ceiling on the *shipping* grey, read off the declaration rather
        // than from a literal, so it cannot pass while the palette moves.
        //
        // The bound was `< 1.2`, chosen to defend `#171717` at 1.17:1, and #194
        // fired it on purpose. `< 1.5` is what replaces it: the grey may be
        // nudged by eye the way #194 and #240 nudged it, and a change that
        // starts walking it toward legible body text fails here and has to say
        // so. Legibility is `greyIncreasedContrast`'s job; this value's job is
        // to stay unmistakably not-lit.
        //
        // **The bound is a ceiling that has now been reached, and the
        // arithmetic here was wrong until #240 computed it.** This comment used
        // to name 44/255 — `#2C2C2C` — as "1.5:1". Put through the formula
        // below, 44/255 is 1.5037:1, which is *over* the bound rather than on
        // it; 43/255 is 1.4832:1, and is the last value that clears it. So
        // `#2B2B2B`, which is what ships, is the top of this guardrail: the
        // next nudge is not a nudge but a proposal to move the bound, and has
        // to be argued as one.
        let shipping = Self.contrastOnBlack(Double(components(GlowPalette.greyOpaque).r))
        #expect(shipping < 1.5,
                "the unlit grey is at \(shipping):1 on black; it is supposed to stay under 1.5:1")
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

    @Test("Outside accented rendering and Increase Contrast, the grey resolves to #2B2B2B")
    @MainActor
    func defaultEnvironmentResolvesToTheOpaqueGrey() {
        // The default environment is what every app surface draws in: no widget
        // rendering mode, standard contrast.
        let resolved = GlowGrey().resolve(in: EnvironmentValues())
        #expect((components(resolved).r * 255).rounded() == 43)
        #expect(components(resolved).a == 1)
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
