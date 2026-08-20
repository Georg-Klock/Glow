import CoreGraphics
import Testing
@testable import Glow

@Suite("Widget row capacity")
struct WidgetMetricsTests {
    /// The large widget, from docs/widget-large-spec.md §1 and §3.4.
    private let largeHeight: CGFloat = 354
    private let largeWidth: CGFloat = 338

    /// The content box, inside the vertical padding.
    private var contentHeight: CGFloat { largeHeight - WidgetMetrics.padVertical * 2 }

    /// The track, and therefore the slot, for the large family.
    private var largeSlot: CGFloat {
        let track = largeWidth
            - WidgetMetrics.padLeading - WidgetMetrics.padTrailing
            - WidgetMetrics.labelWidth - WidgetMetrics.labelGap
        return SlotLayout.slotHeight(trackWidth: track)
    }

    @Test("The large widget holds eleven habits")
    func largeHoldsEleven() {
        // The spec does this by hand in §4 — "n ≤ 11.09, so the widget holds 11
        // rows at this pitch" — and this is the same arithmetic done by the code
        // that lays it out. If the two ever disagree, one of them has drifted.
        #expect(WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: true
        ) == 11)
    }

    @Test("Eleven rows actually fit, and twelve do not")
    func capacityIsTheRealLimit() {
        let available = contentHeight - WidgetMetrics.headerHeight - WidgetMetrics.headerGap
        func height(_ n: Int) -> CGFloat {
            CGFloat(n) * largeSlot + CGFloat(n - 1) * WidgetMetrics.rowGap
        }
        #expect(height(11) <= available)
        #expect(height(12) > available)
    }

    @Test("Dropping the header buys a row")
    func headerCostsARow() {
        let withHeader = WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: true
        )
        let without = WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: false
        )
        #expect(without == withHeader + 1)
    }

    @Test("Degenerate sizes give nothing rather than something negative")
    func degenerateSizes() {
        #expect(WidgetMetrics.rowCapacity(height: 354, slot: 0, hasHeader: false) == 0)
        #expect(WidgetMetrics.rowCapacity(height: 0, slot: 17.5, hasHeader: false) == 0)
        // A header taller than the box leaves no room, and must not wrap around.
        #expect(WidgetMetrics.rowCapacity(height: 10, slot: 17.5, hasHeader: true) == 0)
    }
}
