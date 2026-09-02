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

    @Test("The month title puts the design grid at 32 without moving the weekday header")
    func monthTitleOwnsItsLineBox() {
        #expect(WidgetMetrics.headerHeight == 14)
        #expect(WidgetMetrics.monthTitleHeight == 18)
        #expect(
            WidgetMetrics.padTop
                + WidgetMetrics.monthTitleHeight
                + WidgetMetrics.headerGap == 32
        )
    }

    @Test(
        "Four-, five-, and six-row months split the space below the title",
        arguments: [(4, 19.5), (5, 10.0), (6, 0.5)]
    )
    func shortMonthsCentreTheirRowBlock(rows: Int, expectedOffset: CGFloat) {
        // The small widget's 158pt frame leaves a 134pt content box inside its
        // 10/14 vertical insets. A month cell is 16pt on a 19pt pitch, and the
        // title plus its gap occupies 22pt. These are the authored metrics, so
        // the margins below are the actual 4/5/6-row placements from #505.
        let contentHeight: CGFloat = 158 - WidgetMetrics.padTop - WidgetMetrics.padBottom
        let slot: CGFloat = 16
        let gap: CGFloat = 3
        let header = WidgetMetrics.monthTitleHeight + WidgetMetrics.headerGap
        let offset = WidgetMetrics.rowsOffset(
            contentHeight: contentHeight,
            slot: slot,
            gap: gap,
            rows: rows,
            headerFootprint: header
        )
        let block = CGFloat(rows) * slot + CGFloat(rows - 1) * gap
        let bottom = contentHeight - header - offset - block

        #expect(abs(offset - expectedOffset) < 0.001)
        #expect(abs(offset - bottom) < 0.001)
        if rows == 6 {
            // The file's six-row month stays at y=32.5 — within the deliberate
            // half-point of the y=32 placement #493 established.
            #expect(abs(WidgetMetrics.padTop + header + offset - 32.5) < 0.001)
        }
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

    // MARK: - The frames phones actually give (#410)

    /// The three large frames WidgetKit was measured handing out, and the one
    /// the design is drawn on.
    ///
    /// Read out of WidgetKit's own `snapshot-cache` archive path on each device
    /// — it names the frame it renders into — and confirmed on the 17 Pro by
    /// pixel-counting a placed widget at 3x. **None of them is 338 × 354**, and
    /// every one is proportionally *wider* than it. That is the whole of the
    /// bug: a slot is a row's height as well as a daily mark's width, so ten
    /// rows outgrew the available height by 0.44pt (17e) to 1.97pt (17 Pro),
    /// the floor division took nine, and a habit was missing from every large
    /// widget on every phone.
    ///
    /// Written down as measurements rather than derived, because that is what
    /// they are. They pin three phones, not the phone — `rowLayout` is written
    /// against the *shape* of the problem rather than against these numbers,
    /// and these are here to say the shape was real.
    private static let measuredLargeFrames: [(String, CGSize)] = [
        ("iPhone 15 Pro", CGSize(width: 344.67, height: 360)),
        ("iPhone 17 Pro", CGSize(width: 349.67, height: 365)),
        ("iPhone 17e", CGSize(width: 342, height: 358)),
        ("the design frame", CGSize(width: 338, height: 354)),
    ]

    /// The layout a large `WeekWidgetView` reaches for a frame, by the route
    /// the view itself takes: inset, then track, then `rowLayout`.
    private func largeLayout(_ frame: CGSize) -> (rows: WidgetMetrics.RowLayout, track: CGFloat) {
        let track = frame.width
            - WidgetMetrics.padLeading - WidgetMetrics.padTrailing
            - WidgetMetrics.labelWidth - WidgetMetrics.labelGap
        return (
            WidgetMetrics.rowLayout(
                trackWidth: track,
                contentHeight: frame.height - WidgetMetrics.padTop - WidgetMetrics.padBottom,
                designRows: WidgetMetrics.designRowCount(.systemLarge, hasHeader: true),
                hasHeader: true
            ),
            track
        )
    }

    @Test("Every frame a phone was measured giving draws ten rows, not nine")
    func measuredFramesDrawTenRows() {
        // The regression this file could not have caught before: every
        // assertion above is against 338 × 354, which is the one frame where
        // the old derivation happened to fit. Nine was the answer everywhere
        // else, and the render harness renders only at the design frame, so
        // nothing said so.
        for (name, frame) in Self.measuredLargeFrames {
            #expect(largeLayout(frame).rows.capacity == 10, "\(name) draws nine rows")
        }
    }

    @Test("The rows fill the height exactly, so the bottom margin is padBottom")
    func measuredFramesFillTheHeight() {
        for (name, frame) in Self.measuredLargeFrames {
            let slot = largeLayout(frame).rows.slot
            let available = frame.height - WidgetMetrics.padTop - WidgetMetrics.padBottom
                - WidgetMetrics.headerHeight - WidgetMetrics.headerGap
            let block = 10 * slot + 9 * WidgetMetrics.rowGap
            // To the point, which is what makes the bottom margin `padBottom`
            // and `rowsOffset` zero — the centring #410 reported was the
            // ~31pt a missing row left behind, not a rule about tall frames.
            #expect(abs(block - available) < 0.001, "\(name) does not fill its height")
            #expect(WidgetMetrics.rowsOffset(
                contentHeight: frame.height - WidgetMetrics.padTop - WidgetMetrics.padBottom,
                slot: slot, rows: 10, hasHeader: true
            ) < 0.001, "\(name) still centres a full grid")
        }
    }

    @Test("What it costs is the track, and the cost is under two points")
    func measuredFramesLeaveTheTrackShort() {
        // The stated price of #410's fix, asserted rather than left to be
        // discovered: the marks keep their proportion, so a slot small enough
        // for ten rows draws a track narrower than the frame's, and the
        // difference lands at the trailing edge. The right margin is
        // `padTrailing` plus this, and is no longer exactly 14 on a phone.
        for (name, frame) in Self.measuredLargeFrames {
            let (rows, track) = largeLayout(frame)
            let drawn = SlotLayout.trackWidth(dailySlot: rows.slot)
            let leftover = track - drawn
            #expect(leftover >= -0.001, "\(name) overruns its track")
            #expect(leftover < 2, "\(name) leaves \(leftover)pt of track unused")
            // And the marks shrink by well under a percent — a row that had to
            // give up a tenth of its size to fit would be the wrong trade.
            #expect(rows.slot > SlotLayout.slotHeight(trackWidth: track) * 0.99)
        }
    }

    @Test("The design frame is untouched, which is why the baselines do not move")
    func designFrameIsUnchanged() {
        // The harness renders every frame at `size(of:)`, so this is the
        // assertion that says the committed pictures are unaffected: at the one
        // frame where the width's answer and the height's answer already agree,
        // the slot is the same number it always was.
        let frame = CGSize(width: WidgetMetrics.largeWidth, height: WidgetMetrics.largeHeight)
        let (rows, track) = largeLayout(frame)
        #expect(abs(rows.slot - SlotLayout.slotHeight(trackWidth: track)) < 0.001)
        #expect(abs(SlotLayout.trackWidth(dailySlot: rows.slot) - track) < 0.001)
        #expect(rows.capacity == WidgetMetrics.largeRowCapacity)
    }

    /// The three medium frames WidgetKit was measured handing out, and the one
    /// the design is drawn on (#367).
    ///
    /// Same source as `measuredLargeFrames`: WidgetKit names the frame it
    /// renders into in the archive path it hands the extension, and Glow's own
    /// `snapshot-cache` on each device carries all three. Confirmed by
    /// pixel-counting a *placed* medium widget at 3x on two of them — 1026 ×
    /// 486px on an iPhone 17e and 1049 × 493px on a 17 Pro, which are these
    /// numbers exactly, read off the panel's own edges because
    /// `containerBackground` covers the whole frame.
    ///
    /// **None of them is 338 × 158 either, and for medium that costs nothing.**
    /// That is the finding, and it is the opposite shape to the large family's:
    /// see `designFrameIsTheTightestMediumFit` below for why.
    private static let measuredMediumFrames: [(String, CGSize)] = [
        ("iPhone 15 Pro", CGSize(width: 344.67, height: 162.67)),
        ("iPhone 17 Pro", CGSize(width: 349.67, height: 164.33)),
        ("iPhone 17e", CGSize(width: 342, height: 162)),
        ("the design frame", CGSize(width: 338, height: 158)),
    ]

    /// The layout a medium `WeekWidgetView` reaches for a frame, by the route
    /// the view itself takes. The large family's twin, less the header.
    private func mediumLayout(_ frame: CGSize) -> (rows: WidgetMetrics.RowLayout, track: CGFloat) {
        let track = frame.width
            - WidgetMetrics.padLeading - WidgetMetrics.padTrailing
            - WidgetMetrics.labelWidth - WidgetMetrics.labelGap
        return (
            WidgetMetrics.rowLayout(
                trackWidth: track,
                contentHeight: frame.height - WidgetMetrics.padTop - WidgetMetrics.padBottom,
                designRows: WidgetMetrics.designRowCount(.systemMedium, hasHeader: false),
                hasHeader: false
            ),
            track
        )
    }

    @Test("Every frame a phone was measured giving draws four medium rows")
    func measuredMediumFramesDrawFourRows() {
        // The question #367 was open on: the constant is wrong for medium too,
        // so does medium lose a row the way large did? It does not, on any
        // frame measured — and a placed widget on the 17e and the 17 Pro draws
        // Gratitude, Stretch, Read Book and one blank spacer, which is four.
        #expect(WidgetMetrics.designRowCount(.systemMedium, hasHeader: false) == 4)
        for (name, frame) in Self.measuredMediumFrames {
            #expect(mediumLayout(frame).rows.capacity == 4, "\(name) medium no longer holds four")
        }
    }

    @Test("The medium family keeps every point of its track")
    func mediumIsUntouched() {
        // The height never overrules the width at this family, so #410's rule
        // is inert here and the marks fill the frame's own track exactly —
        // which is why a medium widget's right margin is still `padTrailing` on
        // the point where a large one's is not. Asserted because the rule is
        // applied to both families and "it only affects large" is a claim, not
        // an argument.
        for (name, frame) in Self.measuredMediumFrames {
            let (rows, track) = mediumLayout(frame)
            #expect(abs(rows.slot - SlotLayout.slotHeight(trackWidth: track)) < 0.001,
                    "\(name) medium shrank a slot it did not need to")
            #expect(abs(SlotLayout.trackWidth(dailySlot: rows.slot) - track) < 0.001,
                    "\(name) medium leaves track unused")
        }
    }

    @Test("The design frame is the tightest medium fit, not the loosest")
    func designFrameIsTheTightestMediumFit() {
        // **This is the whole reason #367 costs the medium family nothing**,
        // and it is worth pinning rather than restating, because it inverts the
        // large family's arithmetic.
        //
        // Ten rows fill the design's large frame with zero slack, so a frame
        // proportionally wider than it overran the height and lost a row.
        // Four rows fill only 120 of a medium's 134pt of content, and the
        // division that counts them lands at 4.4375 on the design frame against
        // 4.45–4.50 on the three phones. Every phone measured is therefore
        // *slacker* than the frame the render harness draws, so the harness is
        // conservative here rather than blind — the mirror image of #410, where
        // it was the one frame the fit held on.
        //
        // Written as a comparison rather than as four literals: what matters is
        // the ordering, and the ordering is what would have to change for a
        // wrong constant to start costing this family a row.
        func headroom(_ frame: CGSize) -> CGFloat {
            let (rows, _) = mediumLayout(frame)
            let available = frame.height - WidgetMetrics.padTop - WidgetMetrics.padBottom
            // How many rows the floor division was dividing, before the floor.
            return (available + WidgetMetrics.rowGap) / (rows.slot + WidgetMetrics.rowGap)
        }
        let design = headroom(CGSize(width: WidgetMetrics.largeWidth, height: WidgetMetrics.smallSide))
        #expect(design > 4, "the design frame no longer holds four medium rows")
        for (name, frame) in Self.measuredMediumFrames where name != "the design frame" {
            #expect(headroom(frame) > design,
                    "\(name) is a tighter medium fit than the design frame")
        }
    }

    @Test("A frame too small for the design's rows falls back rather than vanishing")
    func degenerateFramesFallBack() {
        // A `GeometryReader` reports zero on its first pass often enough not to
        // be theoretical, and a zero frame must not claim ten rows.
        let zero = WidgetMetrics.rowLayout(
            trackWidth: 0, contentHeight: 0, designRows: 10, hasHeader: true
        )
        #expect(zero.slot == 0)
        #expect(zero.capacity == 0)
        let noRows = WidgetMetrics.rowLayout(
            trackWidth: 216, contentHeight: 330, designRows: 0, hasHeader: true
        )
        #expect(noRows.slot == SlotLayout.slotHeight(trackWidth: 216))
    }

    @Test("Degenerate sizes give nothing rather than something negative")
    func degenerateSizes() {
        #expect(WidgetMetrics.rowCapacity(height: 354, slot: 0, hasHeader: false) == 0)
        #expect(WidgetMetrics.rowCapacity(height: 0, slot: 17.5, hasHeader: false) == 0)
        // A header taller than the box leaves no room, and must not wrap around.
        #expect(WidgetMetrics.rowCapacity(height: 10, slot: 17.5, hasHeader: true) == 0)
    }
}
