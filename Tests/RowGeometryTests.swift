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
            ("contentWidth", geometry.contentWidth),
            ("editControlOverhang", geometry.editControlOverhang),
            ("editingNameMaxWidth", geometry.editingNameMaxWidth),
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

    /// #458: the step faces breathe evenly inside the frequency platter.
    /// These are production values rather than a scan of the view's source,
    /// and the subtraction is the relationship the eye sees.
    @Test("The step faces leave ten points at every outer edge")
    func editorStepMargins() {
        #expect(HabitEditorGeometry.rowHeight == 56)
        #expect(HabitEditorGeometry.stepInset == 10)
        #expect(HabitEditorGeometry.stepSize == CGSize(width: 44, height: 36))
        #expect(
            (HabitEditorGeometry.rowHeight - HabitEditorGeometry.stepSize.height) / 2
                == HabitEditorGeometry.stepInset
        )
        #expect(HabitEditorGeometry.stepRadius == 16)
        #expect(HabitEditorGeometry.stepRadius < HabitEditorGeometry.stepSize.height / 2)
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

    /// #455: the two visible requests and the room they create are one rule.
    /// Pin the production values directly; the ratio check above would stay
    /// green if both app and widget agreed on the wrong geometry.
    @Test("The icon matches the name and the two half-gaps grant 69.5 points")
    func iconAndNameGeometry() {
        #expect(WidgetMetrics.iconSize == WidgetMetrics.textSize)
        #expect(WidgetMetrics.iconGap == 2.25)
        #expect(WidgetMetrics.nameMaxWidth == 69.5)
        #expect(
            WidgetMetrics.nameMaxWidth
                == WidgetMetrics.labelWidth - WidgetMetrics.iconWidth
                    - WidgetMetrics.iconGap - WidgetMetrics.iconGap
        )
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

    /// #440: while the list is being edited the row is not a label column and
    /// a track, it is one width with a centred name in it — so the cap on the
    /// name is a different number, and it is the one the row grants.
    ///
    /// Summed here from the primitives `HabitRowView` actually lays out, so
    /// that this is a second opinion about the arrangement rather than the same
    /// expression written twice: the editing `HStack` is a spacer, the label
    /// and a spacer with `labelGap` between each pair, the label is the icon's
    /// column, `iconGap` and the name, and each end reserves the part of the
    /// row the system's edit controls cover.
    @Test("Editing measures the name against the row, not against the track")
    func editingNameRunIsTheRowsOwnWidth() {
        for width in [200, 320, 338, 353, 393, 402, 430, 1024] as [CGFloat] {
            let g = RowGeometry(totalWidth: width)
            let summed = g.contentWidth
                - g.editControlOverhang - g.labelGap
                - g.iconWidth - g.iconGap
                - g.labelGap - g.editControlOverhang
            #expect(
                abs(g.editingNameMaxWidth - summed) < 1e-9,
                "editing grants \(g.editingNameMaxWidth) at width \(width), not \(summed)"
            )
            // And it is the larger of the two, which is the whole of the bug:
            // the track's width comes back to the name, so the editing cap
            // cannot be the one measured against a track that is not drawn.
            #expect(
                g.editingNameMaxWidth > g.nameMaxWidth,
                "editing grants \(g.editingNameMaxWidth) against \(g.nameMaxWidth) at \(width)"
            )
            // The label it caps still fits the row it is centred in, which is
            // what keeps both spacers non-negative.
            #expect(
                g.editingNameMaxWidth + g.iconWidth + g.iconGap <= g.contentWidth
            )
        }
    }

    /// The controls stand *over* the row, so the clearance is a difference and
    /// a narrow proposal drives it negative — `nameMaxWidth`'s failure, at a
    /// different property. Covered by `everyWidthIsAWidth` as well; named here
    /// because the degenerate end is where a difference goes wrong.
    @Test("A row narrower than the controls still grants a width")
    func editingNameRunIsNeverNegative() {
        for width in [0, 1, 10, 40, 100] as [CGFloat] {
            let g = RowGeometry(totalWidth: width)
            #expect(g.editingNameMaxWidth >= 0)
            #expect(g.editControlOverhang >= 0)
        }
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
