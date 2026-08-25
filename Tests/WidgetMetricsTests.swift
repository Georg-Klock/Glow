import CoreGraphics
import Testing
@testable import Glow

@Suite("Widget row capacity")
struct WidgetMetricsTests {
    /// The large widget's own size, as `WidgetMetrics` declares it.
    private var largeHeight: CGFloat { WidgetMetrics.largeHeight }
    private var largeWidth: CGFloat { WidgetMetrics.largeWidth }

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
        // Eleven is not a stored number anywhere: it falls out of the content
        // height, the derived slot and the row gap. Asserting it here is what
        // stops a change to any of those three quietly changing the capacity.
        #expect(WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: true
        ) == 11)
    }

    @Test("The shared capacity is the same eleven")
    func sharedCapacityAgrees() {
        // The app reads this to decide where to draw the line marking what the
        // widget can show. A second copy of the figure would be one that drifts.
        #expect(WidgetMetrics.largeRowCapacity == 11)
        #expect(WidgetMetrics.largeRowCapacity == WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: true
        ))
    }

    @Test("The medium widget holds five habits, by one point")
    func mediumHoldsFive() {
        // The medium family on the same 6.1" phone the file is authored for:
        // the same width, and so the same track and the same slot, in 158pt of
        // height with no header.
        //
        // Five is the whole of #57. It was four, missing by 0.05 of a row, and
        // `padVertical` gave up the point that closes it. This test is the
        // guard on that point: put 16 back and the count silently returns to
        // four, which is exactly how it went unnoticed the first time.
        let mediumHeight: CGFloat = 158
        #expect(WidgetMetrics.rowCapacity(
            height: mediumHeight - WidgetMetrics.padVertical * 2,
            slot: largeSlot,
            hasHeader: false
        ) == 5)

        // And it really is one point of margin, not a rounding artifact: the
        // file's own 16 gives four.
        #expect(WidgetMetrics.rowCapacity(
            height: mediumHeight - 16 * 2, slot: largeSlot, hasHeader: false
        ) == 4)
    }

    @Test("A configured medium widget is a choice among five, not a dial")
    func mediumHasNoSixthRow() {
        // What #188 can and cannot offer. Choosing *which* five rows a medium
        // widget shows is free; choosing six is not, and no amount of
        // configuration buys one.
        //
        // **There is no `mediumRowCapacity`, and no `smallRowCapacity`**
        // (#188). Configuring a widget's rows was expected to need them, and
        // it does not: `WeekWidgetView` already measures its own frame and
        // cuts the list with `rowCapacity`, so the number below is what a 6.1"
        // phone asks for rather than what the code stores. A stored per-family
        // constant would be this phone's answer applied to every other one — a
        // medium widget is 338 × 158 here and larger on a 6.7".
        // `largeRowCapacity` exists for a different job: the *app* draws a
        // boundary hairline and needs one number to draw it at. The margin is 0.72pt — five rows need 127.28
        // of 128 — and both candidate donors are already spoken for:
        // `padVertical` gave its point to buy the fifth row (#57), and `rowGap`
        // is set by how far a halo spills out of a row.
        let mediumHeight: CGFloat = 158
        let content = mediumHeight - WidgetMetrics.padVertical * 2
        func height(_ n: Int) -> CGFloat {
            CGFloat(n) * largeSlot + CGFloat(n - 1) * WidgetMetrics.rowGap
        }
        #expect(height(5) <= content)
        #expect(height(6) > content)
    }

    @Test("The large widget's eleven survives the point")
    func largeIsUnaffectedByThePoint() {
        // `padVertical` moved for the medium family's sake, and the large one
        // must not have moved with it. Its spare change was never within a
        // point of the next row, and this says so rather than trusting it.
        #expect(WidgetMetrics.rowCapacity(
            height: largeHeight - 16 * 2, slot: largeSlot, hasHeader: true
        ) == 11)
        #expect(WidgetMetrics.largeRowCapacity == 11)
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
