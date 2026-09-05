import CoreGraphics
import SwiftUI
import Testing
@testable import Glow

/// #567: the name may grow into the icon's column, and only when both the
/// person and the phone have asked for it.
@Suite("Large text drops the icon")
struct LargeTextPolicyTests {
    private static let raised: [DynamicTypeSize] = [
        .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]
    private static let notRaised: [DynamicTypeSize] = [.xSmall, .small, .medium, .large]

    @Test("Off, the row is the design's at every type size")
    func offIsStandard() {
        for size in Self.raised + Self.notRaised {
            #expect(LargeTextPolicy.layout(dropsIcon: false, size: size) == .standard)
        }
        #expect(LargeTextPolicy.Layout.standard.showsIcon)
        #expect(LargeTextPolicy.Layout.standard.textSize == WidgetMetrics.textSize)
    }

    @Test("On, the row is still the design's at and below the default size")
    func onAtDefaultIsStandard() {
        for size in Self.notRaised {
            #expect(LargeTextPolicy.layout(dropsIcon: true, size: size) == .standard)
        }
    }

    @Test("Any step above the default drops the icon and grows the name")
    func anyRaisedStepGrows() {
        for size in Self.raised {
            let layout = LargeTextPolicy.layout(dropsIcon: true, size: size)
            #expect(!layout.showsIcon, "\(size)")
            #expect(layout.textSize > WidgetMetrics.textSize, "\(size)")
            #expect(layout.textSize <= WidgetMetrics.textSizeCap, "\(size)")
        }
    }

    @Test("The name grows at the rate body text does, then holds at the cap")
    func growthFollowsBodyThenCaps() {
        // 12 × 19/17, 12 × 21/17, 12 × 23/17, 12 × 28/17 — the HIG's body sizes.
        #expect(abs(LargeTextPolicy.textSize(for: .xLarge) - 13.41) < 0.01)
        #expect(abs(LargeTextPolicy.textSize(for: .xxLarge) - 14.82) < 0.01)
        #expect(abs(LargeTextPolicy.textSize(for: .xxxLarge) - 16.24) < 0.01)
        #expect(abs(LargeTextPolicy.textSize(for: .accessibility1) - 19.76) < 0.01)
        // 12 × 33/17 is 23.3; the cap is a hard 20 from here on.
        for size in [DynamicTypeSize.accessibility2, .accessibility3, .accessibility4, .accessibility5] {
            #expect(LargeTextPolicy.textSize(for: size) == WidgetMetrics.textSizeCap, "\(size)")
        }
        // Monotonic: a larger setting never gives a smaller name.
        let sizes = Self.notRaised + Self.raised
        let names = sizes.map(LargeTextPolicy.textSize(for:))
        #expect(names == names.sorted())
    }

    @Test("Without the icon the name has the whole label column")
    func nameReclaimsTheIconColumn() {
        let standard = LargeTextPolicy.Layout.standard.nameMaxWidth(
            labelWidth: WidgetMetrics.labelWidth,
            iconWidth: WidgetMetrics.iconWidth,
            iconGap: WidgetMetrics.iconGap
        )
        #expect(standard == WidgetMetrics.nameMaxWidth)

        let grown = LargeTextPolicy.layout(dropsIcon: true, size: .accessibility1)
        let width = grown.nameMaxWidth(
            labelWidth: WidgetMetrics.labelWidth,
            iconWidth: WidgetMetrics.iconWidth,
            iconGap: WidgetMetrics.iconGap
        )
        #expect(width == WidgetMetrics.labelWidth)
        #expect(width - standard == WidgetMetrics.iconWidth + WidgetMetrics.iconGap)
        // Never negative, whichever branch (#136).
        #expect(grown.nameMaxWidth(labelWidth: -1, iconWidth: 24, iconGap: 2) == 0)
        #expect(LargeTextPolicy.Layout.standard.nameMaxWidth(labelWidth: 10, iconWidth: 24, iconGap: 2) == 0)
    }

    @Test("The setting round-trips through the App Group defaults, off by default")
    func settingRoundTrips() {
        GlowSettings.store.removeObject(forKey: GlowSettings.largeTextKey)
        defer { GlowSettings.store.removeObject(forKey: GlowSettings.largeTextKey) }
        #expect(GlowSettings.largeTextDropsIcon == false)
        GlowSettings.largeTextDropsIcon = true
        #expect(GlowSettings.largeTextDropsIcon)
        #expect(GlowSettings.store.bool(forKey: GlowSettings.largeTextKey))
    }
}
