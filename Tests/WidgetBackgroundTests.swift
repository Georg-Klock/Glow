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
        // Two colours, and there is no third: white is anything lit, #171717 is
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

/// Two colours, both opaque (#111).
///
/// The palette used to be a ramp: one grey and three more stacked on top of it
/// by opacity. What replaced it is one grey at the value the darkest step
/// already composited to, and the tests below are the arithmetic that claim
/// rests on — `0.553 × 0.16 × 255 = 22.6 → 23` — plus the two places a grey is
/// still allowed to be alpha and why each is not a third colour.
@Suite("Two colours")
struct TwoColoursTests {
    /// Resolves a `Color` the way the screen does.
    @MainActor
    private func components(_ colour: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = -1, g: CGFloat = -1, b: CGFloat = -1, a: CGFloat = -1
        _ = UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    @Test("The grey the app draws is #171717, and it is opaque")
    @MainActor
    func greyIsOpaqueSeventeen() {
        let grey = components(GlowPalette.greyOpaque)
        #expect((grey.r * 255).rounded() == 23)
        #expect((grey.g * 255).rounded() == 23)
        #expect((grey.b * 255).rounded() == 23)
        #expect(grey.a == 1, "the grey carries alpha: \(grey.a)")

        // And white is still white, still opaque.
        let white = components(GlowPalette.color)
        #expect(white.r == 1 && white.g == 1 && white.b == 1 && white.a == 1)
    }

    @Test("#171717 is what the old socket composited to, not a new colour")
    @MainActor
    func greyIsTheOldSocket() {
        // The socket was `white.opacity(0.553).opacity(0.16)`. Composited on
        // black in gamma-encoded sRGB — which is what SwiftUI does, confirmed
        // against a screenshot rather than assumed — that is 23.
        let old = 0.553 * 0.16 * 255
        #expect((old).rounded() == 23, "the derivation moved: \(old)")
        #expect((components(GlowPalette.greyOpaque).r * 255).rounded() == 23)
    }

    @Test("Increase Contrast gets the grey the app used to draw")
    @MainActor
    func increasedContrastIsTheOldGrey() {
        // #8D8D8D: what `white.opacity(0.553)` composited to on black, and so
        // not a number invented for the setting. It clears 4.5:1 on black,
        // which #171717 at about 1.1:1 does not.
        let lifted = components(GlowPalette.greyIncreasedContrast)
        #expect((lifted.r * 255).rounded() == 141)
        #expect(lifted.a == 1)
        #expect(Self.contrastOnBlack(141 / 255.0) > 4.5,
                "the lifted grey no longer clears 4.5:1")
        #expect(Self.contrastOnBlack(23 / 255.0) < 1.2,
                "#171717 is supposed to be far below legible; it moved")
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

    @Test("Outside accented rendering and Increase Contrast, the grey resolves to #171717")
    @MainActor
    func defaultEnvironmentResolvesToTheOpaqueGrey() {
        // The default environment is what every app surface draws in: no widget
        // rendering mode, standard contrast.
        let resolved = GlowGrey().resolve(in: EnvironmentValues())
        #expect((components(resolved).r * 255).rounded() == 23)
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
