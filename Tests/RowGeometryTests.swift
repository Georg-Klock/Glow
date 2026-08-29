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
