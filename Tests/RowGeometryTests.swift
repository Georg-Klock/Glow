import Foundation
import Testing
@testable import Glow

/// #136: every width a row hands to a frame modifier has to be a width.
///
/// The suite was logging `Invalid frame dimension (negative or non-finite)` at
/// test-host startup, and `RowGeometry` had a direct arithmetic path to it:
/// `nameMaxWidth` is a *difference*, so a label column squeezed to nothing by a
/// narrow proposal takes it below zero and it goes straight into
/// `.frame(maxWidth:)`.
@Suite("Row geometry")
struct RowGeometryTests {
    /// Every value the row reads off this type, by name so a failure says which.
    private func values(_ geometry: RowGeometry) -> [(String, CGFloat)] {
        [
            ("scale", geometry.scale),
            ("labelWidth", geometry.labelWidth),
            ("trackWidth", geometry.trackWidth),
            ("textSize", geometry.textSize),
            // `horizontalPadding` was one value on both sides and is now the
            // widget's asymmetric pair, plus the frame insets the screen took
            // on when it had to be a large widget scaled up. Enumerated here
            // because this list is the type's surface: a property that is not
            // in it is a property nothing checks is a width.
            ("padLeading", geometry.padLeading),
            ("padTrailing", geometry.padTrailing),
            ("padTop", geometry.padTop),
            ("padBottom", geometry.padBottom),
            ("headerHeight", geometry.headerHeight),
            ("headerGap", geometry.headerGap),
            ("labelGap", geometry.labelGap),
            ("rowInset", geometry.rowInset),
            ("iconSize", geometry.iconSize),
            ("iconWidth", geometry.iconWidth),
            ("iconGap", geometry.iconGap),
            ("nameMaxWidth", geometry.nameMaxWidth),
            ("slotHeight", geometry.slotHeight),
            ("panelHeight(0)", geometry.panelHeight(rows: 0)),
            ("panelHeight(1)", geometry.panelHeight(rows: 1)),
            ("panelHeight(11)", geometry.panelHeight(rows: 11)),
        ]
    }

    @Test("Nothing is negative or non-finite, at any proposal")
    func everyWidthIsAWidth() {
        // Zero is the first pass of every `GeometryReader`; the narrow ones are
        // where `nameMaxWidth` went to −13.5pt; the last two are what layout
        // hands over when it has not decided yet.
        let proposals: [CGFloat] = [
            0, 1, 10, 40, 100, 200, 338, 402, 430, 1024, 2048,
            -1, -1000, .infinity, -.infinity, .nan,
        ]
        for width in proposals {
            let geometry = RowGeometry(totalWidth: width)
            for (name, value) in values(geometry) {
                #expect(value.isFinite, "\(name) is not finite at width \(width)")
                #expect(value >= 0, "\(name) is \(value) at width \(width)")
            }
        }
    }

    @Test("The case the warning came from")
    func zeroWidth() {
        // Named on its own because it is the reported one, and because a
        // regression here would otherwise hide inside the sweep above.
        let geometry = RowGeometry(totalWidth: 0)
        #expect(geometry.nameMaxWidth == 0)
        #expect(geometry.trackWidth == 0)
        #expect(geometry.labelWidth == 0)
    }

    @Test("Clamping did not flatten a real layout")
    func normalWidthIsUnchanged() {
        // The floors must only catch the degenerate end. At a phone's width the
        // label column, the track and the name's run are all positive and the
        // track is the larger part of the row.
        let geometry = RowGeometry(totalWidth: 402)
        #expect(geometry.labelWidth > 0)
        #expect(geometry.nameMaxWidth > 0)
        #expect(geometry.trackWidth > geometry.labelWidth)
        // And the name may still run past its icon into the gap, which is the
        // rule `nameMaxWidth` exists to express.
        #expect(geometry.nameMaxWidth > geometry.iconWidth)
    }

    /// #398: the panel is one shape now, so it has to be *told* how tall it is.
    ///
    /// The `List` used to answer this by construction — the panel was the row
    /// backgrounds, so it could not be the wrong height. Summed here from the
    /// same primitives `WeeklyGridView` gives its rows, independently of
    /// `panelHeight`'s own expression: a header block, then every row with the
    /// insets the grid sets on it, the last one standing `padBottom` off the
    /// edge instead of `rowInset`.
    @Test("The panel is exactly as tall as the rows on it")
    func panelHeightMatchesTheRows() {
        for width in [338, 402, 430, 1024] as [CGFloat] {
            let g = RowGeometry(totalWidth: width)
            for rows in 1...12 {
                let header = g.padTop + g.headerHeight
                    + (g.headerGap - WidgetMetrics.rowGap * g.scale / 2)
                var summed = header
                for index in 0..<rows {
                    summed += g.rowInset + g.slotHeight
                    summed += index == rows - 1 ? g.padBottom : g.rowInset
                }
                #expect(
                    abs(g.panelHeight(rows: rows) - summed) < 0.0001,
                    "width \(width), rows \(rows): \(g.panelHeight(rows: rows)) vs \(summed)"
                )
            }
        }
    }

    /// An empty store shows the empty state, not a grid — so there is no panel
    /// to draw, and asking for one must not produce a header-shaped sliver.
    @Test("No rows, no panel")
    func noRowsNoPanel() {
        #expect(RowGeometry(totalWidth: 402).panelHeight(rows: 0) == 0)
        #expect(RowGeometry(totalWidth: 0).panelHeight(rows: 0) == 0)
    }

    /// Each row adds the same amount, which is what makes the panel end under
    /// the last one rather than drifting as the list grows.
    @Test("Every row past the first adds one row's height")
    func panelGrowsByOneRow() {
        let g = RowGeometry(totalWidth: 402)
        let step = g.panelHeight(rows: 3) - g.panelHeight(rows: 2)
        #expect(step > 0)
        for rows in 2...11 {
            #expect(
                abs((g.panelHeight(rows: rows + 1) - g.panelHeight(rows: rows)) - step) < 0.0001
            )
        }
    }

    /// #405 assumed the screen and the widget could disagree about where a name
    /// is cut, which would mean no single creation-time preview could be honest
    /// about both. They cannot disagree: this type applies one factor to the
    /// label column *and* to the text size, so the ratio between the two is the
    /// widget's ratio at every width. `HabitEditorView`'s preview rests on this.
    @Test("A name is cut at the same character on the screen as in the widget")
    func nameRunIsTheWidgetsRatio() {
        let widget = WidgetMetrics.nameMaxWidth / WidgetMetrics.textSize
        for width in [1, 100, 200, 320, 338, 353, 402, 430, 1024] as [CGFloat] {
            let geometry = RowGeometry(totalWidth: width)
            let screen = geometry.nameMaxWidth / geometry.textSize
            #expect(
                abs(screen - widget) < 1e-9,
                "the name runs \(screen) text-sizes at width \(width), not \(widget)"
            )
        }
    }

    /// And at the widget's own width it is not merely the same ratio but the
    /// same numbers, which is the scale the editor's preview renders at.
    @Test("At 338 the screen's row is the widget's row")
    func atTheWidgetsOwnWidth() {
        let geometry = RowGeometry(totalWidth: WidgetMetrics.largeWidth)
        #expect(geometry.scale == 1)
        #expect(geometry.nameMaxWidth == WidgetMetrics.nameMaxWidth)
        #expect(geometry.textSize == WidgetMetrics.textSize)
        #expect(geometry.iconWidth == WidgetMetrics.iconWidth)
        #expect(geometry.iconGap == WidgetMetrics.iconGap)
    }

    /// #400: the grid's 20pt margin is now paid in two instalments, and the
    /// sum is the whole point.
    ///
    /// `WeeklyGridView` narrows the `List` by `editControlInset` so that the
    /// delete circle and the reorder handle — which are the system's, laid out
    /// against the `List`'s bounds and deaf to `listRowInsets` — come off the
    /// panel's edge, and hands the same amount back to the rows and the panel
    /// as `rowPadding`. Every absolute position on the screen is unchanged
    /// only while the two add up; a number moved on one side and not the other
    /// slides the whole grid, and it slides it by an amount small enough to be
    /// read as a rendering difference rather than as a bug.
    @Test("The list's inset and the rows' add back up to the grid's margin")
    func theTwoInstalmentsSumToTheMargin() {
        #expect(
            GridMetrics.rowPadding + GridMetrics.editControlInset
                == GridMetrics.horizontalPadding
        )
        // Neither end is allowed to be the whole thing. At zero there is no
        // breathing room and #400 is not fixed; at the full margin the rows
        // would inset by nothing and the panel would be drawn edge to edge.
        #expect(GridMetrics.editControlInset > 0)
        #expect(GridMetrics.rowPadding > 0)
    }

    @Test("A non-finite proposal is treated as no width, not as a huge one")
    func infinityIsNotAScreen() {
        // `.infinity` reaching `scale` would scale every metric to infinity and
        // the failure would surface far from here.
        let infinite = RowGeometry(totalWidth: .infinity)
        let zero = RowGeometry(totalWidth: 0)
        #expect(infinite.scale == zero.scale)
        #expect(infinite.trackWidth == zero.trackWidth)
    }
}
