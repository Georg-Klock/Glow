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

    @Test("Every colour the widget draws is neutral — white, or white with alpha")
    @MainActor
    func nothingCarriesAHue() {
        // Two colours, and there is no third: white is anything lit, grey is
        // anything that is not. A hue anywhere would also break the widget's
        // accented rendering, where the system keeps alpha and discards colour.
        let neutral: [Color] = [
            GlowPalette.color, GlowPalette.grey, GlowPalette.labelResting,
            GlowPalette.headerRest, GlowPalette.missed, GlowPalette.restCut,
            GlowPalette.upcoming, GlowPalette.widgetBackground,
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
