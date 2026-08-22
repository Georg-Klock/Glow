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
            ("horizontalPadding", geometry.horizontalPadding),
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
