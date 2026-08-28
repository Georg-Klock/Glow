import CoreGraphics
import Testing
@testable import Glow

@Suite("Widget row capacity")
struct WidgetMetricsTests {
    /// The large widget's own size, as `WidgetMetrics` declares it.
    private var largeHeight: CGFloat { WidgetMetrics.largeHeight }
    private var largeWidth: CGFloat { WidgetMetrics.largeWidth }

    /// The content box, inside the vertical padding.
    private var contentHeight: CGFloat {
        largeHeight - WidgetMetrics.padTop - WidgetMetrics.padBottom
    }

    /// The track, and therefore the slot, for the large family.
    private var largeSlot: CGFloat {
        let track = largeWidth
            - WidgetMetrics.padLeading - WidgetMetrics.padTrailing
            - WidgetMetrics.labelWidth - WidgetMetrics.labelGap
        return SlotLayout.slotHeight(trackWidth: track)
    }

    @Test("The large widget holds ten habits")
    func largeHoldsTen() {
        // **Eleven until #331.** Ten is not a stored number anywhere either: it
        // falls out of the content height, the derived slot and the row gap,
        // and asserting it here is what stops a change to any of those three
        // quietly changing the capacity.
        //
        // It also falls out exactly, which is new. `9 × 32 + 24 = 312` is the
        // track height to the point, where eleven rows used to fit with change
        // left over.
        #expect(WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: true
        ) == 10)
    }

    @Test("The shared capacity is the same ten")
    func sharedCapacityAgrees() {
        // The app reads this to decide where to draw the line marking what the
        // widget can show. A second copy of the figure would be one that drifts.
        #expect(WidgetMetrics.largeRowCapacity == 10)
        #expect(WidgetMetrics.largeRowCapacity == WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: true
        ))
    }

    @Test("The medium widget holds four habits, and no inset buys a fifth")
    func mediumHoldsFour() {
        // The medium family on the same 6.1" phone the file is authored for:
        // the same width, and so the same track and the same slot, in 158pt of
        // height with no header.
        //
        // **Five until #331, and this is the change's real cost.** #57 spent a
        // point of `padVertical` to buy the fifth row — 126pt of content
        // against a 27.45pt pitch was 4.95 rows and the hard cut took the
        // floor. The slot is 24 now rather than 17.455, so a medium widget
        // shows four habits and one point cannot change that.
        let mediumHeight: CGFloat = 158
        #expect(WidgetMetrics.rowCapacity(
            height: mediumHeight - WidgetMetrics.padTop - WidgetMetrics.padBottom,
            slot: largeSlot,
            hasHeader: false
        ) == 4)

        // #57's move is not merely spent, it is out of reach: a whole point off
        // each inset does not reach a row boundary at this slot size, which is
        // why the insets are now the design's own numbers with nothing
        // borrowed.
        #expect(WidgetMetrics.rowCapacity(
            height: mediumHeight - 16 * 2, slot: largeSlot, hasHeader: false
        ) == 4)
    }

    @Test("A configured medium widget is a choice among four, not a dial")
    func mediumHasNoFifthRow() {
        // What #188 can and cannot offer. Choosing *which* rows a medium widget
        // shows is free; choosing one more is not, and no amount of
        // configuration buys it.
        //
        // **There is no `mediumRowCapacity`, and no `smallRowCapacity`**
        // (#188). Configuring a widget's rows was expected to need them, and
        // it does not: `WeekWidgetView` already measures its own frame and
        // cuts the list with `rowCapacity`, so the number below is what a 6.1"
        // phone asks for rather than what the code stores. A stored per-family
        // constant would be this phone's answer applied to every other one — a
        // medium widget is 338 × 158 here and larger on a 6.7".
        // `largeRowCapacity` exists for a different job: the *app* draws a
        // boundary hairline and needs one number to draw it at.
        //
        // **The margin is no longer hundredths.** #57's fifth row missed by
        // 0.72pt of 128 and one point of inset closed it. A fifth row at a 24pt
        // slot needs 152 of 134 — eighteen points short, which is not a number
        // any inset in this frame can find.
        let mediumHeight: CGFloat = 158
        let content = mediumHeight - WidgetMetrics.padTop - WidgetMetrics.padBottom
        func height(_ n: Int) -> CGFloat {
            CGFloat(n) * largeSlot + CGFloat(n - 1) * WidgetMetrics.rowGap
        }
        #expect(height(4) <= content)
        #expect(height(5) > content)
    }

    @Test("Ten rows use every point the large frame has, and the insets are load-bearing")
    func largeCapacityHasNoSlack() {
        // This used to guard #57's arrangement — `padVertical` one point off
        // the design's for the medium family's sake, and the large family
        // unaffected by it, because its spare change was never near a row
        // boundary. **Both halves of that are now false**, and the second is
        // the one worth knowing.
        //
        // Ten rows fill the track exactly (312 of 312), so the large family has
        // no spare change at all. The design's asymmetric insets give 330 of
        // content; the symmetric 16 this once compared against gives 322, and
        // those 8 points — a quarter of one row's pitch — are the difference
        // between ten rows and nine.
        //
        // So the insets are load-bearing in a way they were not before, which
        // is exactly the kind of thing #57 shows goes unnoticed. Pinned here.
        #expect(WidgetMetrics.largeRowCapacity == 10)
        #expect(WidgetMetrics.rowCapacity(
            height: largeHeight - 16 * 2, slot: largeSlot, hasHeader: true
        ) == 9, "the large capacity no longer sits hard against its insets")
    }

    @Test("Ten rows actually fit, and eleven do not — exactly")
    func capacityIsTheRealLimit() {
        let available = contentHeight - WidgetMetrics.headerHeight - WidgetMetrics.headerGap
        func height(_ n: Int) -> CGFloat {
            CGFloat(n) * largeSlot + CGFloat(n - 1) * WidgetMetrics.rowGap
        }
        // **Exactly, which is new.** `9 × 32 + 24 = 312` and the track is 312:
        // ten rows fill it to the point, where eleven used to fit with change
        // left over. That is §8.2's claim about the grid, checked here from the
        // capacity side.
        #expect(height(10) == available)
        #expect(height(11) > available)
    }

    @Test("The header is free at this geometry, where it used to cost a row")
    func headerCostsNothing() {
        // **It used to buy one, and #331 stops it.** The header and its gap
        // were 27 points against a 27.455pt row pitch — almost exactly a row,
        // so dropping it bought one. They are 18 against a 32pt pitch now, and
        // the large frame has exactly 18 points of slack under its ten rows
        // (330 of content, 312 of track), so the header lands in the space
        // already there.
        //
        // Asserted rather than left as an accident: if either number moves, one
        // family silently gains or loses a habit, which is how #57 went
        // unnoticed the first time.
        let withHeader = WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: true
        )
        let without = WidgetMetrics.rowCapacity(
            height: contentHeight, slot: largeSlot, hasHeader: false
        )
        #expect(withHeader == 10)
        #expect(without == withHeader)
    }

    @Test("Degenerate sizes give nothing rather than something negative")
    func degenerateSizes() {
        #expect(WidgetMetrics.rowCapacity(height: 354, slot: 0, hasHeader: false) == 0)
        #expect(WidgetMetrics.rowCapacity(height: 0, slot: 17.5, hasHeader: false) == 0)
        // A header taller than the box leaves no room, and must not wrap around.
        #expect(WidgetMetrics.rowCapacity(height: 10, slot: 17.5, hasHeader: true) == 0)
    }
}
