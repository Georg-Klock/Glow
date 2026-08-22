import CoreGraphics
import Testing
@testable import Glow

/// #75's sizing table, and the guards around it.
@Suite("Day ring geometry")
struct DayRingGeometryTests {
    /// The three diameters the app and the two widgets actually draw.
    private let sizes: [CGFloat] = [92, 96, 76]

    private func isNear(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool {
        abs(a - b) < tolerance
    }

    @Test("The issue's table, at all three ring sizes")
    func theTable() {
        // diameter, band, hairline, corner radius — read off #75.
        let expected: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (92, 7.886, 1.577, 1.971),
            (96, 8.229, 1.646, 2.057),
            (76, 6.514, 1.303, 1.629),
        ]
        for (diameter, band, hairline, corner) in expected {
            let g = DayRingGeometry(diameter: diameter)
            #expect(isNear(g.band, band), "band at \(diameter)")
            #expect(isNear(g.hairline, hairline), "hairline at \(diameter)")
            // A half-circle span is nowhere near the clamp, so this is the
            // unclamped quarter-band.
            #expect(isNear(g.cornerRadius(span: 0.5), corner), "corner at \(diameter)")
        }
    }

    @Test("The hairline is a fifth of the band, at every size")
    func hairlineIsAFifthOfTheBand() {
        // One constant for the pill's outline and the logged line both, which
        // is what makes the ring read as one drawing.
        for diameter in sizes {
            let g = DayRingGeometry(diameter: diameter)
            #expect(isNear(g.hairline * 5, g.band), "at \(diameter)")
        }
    }

    @Test("The pill occupies exactly the annulus the old stroke did")
    func theRingKeepsItsDiameter() {
        // #75's hard requirement: the ring's outer diameter does not move.
        for diameter in sizes {
            let g = DayRingGeometry(diameter: diameter)
            #expect(isNear(g.outerRadius, diameter / 2), "outer at \(diameter)")
            #expect(isNear(g.innerRadius, diameter / 2 - g.band), "inner at \(diameter)")
            // The logged line sits on the centreline, so the silhouette reads
            // at the same diameter whether a repetition is open or done.
            #expect(isNear(g.centreRadius, diameter / 2 - g.band / 2), "centre at \(diameter)")
        }
    }

    @Test("The corner clamp is dormant at every supported count")
    func cornerClampDoesNotBind() {
        // The tightest supported case is twelve repetitions on the 76pt widget
        // ring. If the clamp ever starts binding, a pill's corners stop being
        // a quarter of the band and the three sizes stop being one drawing.
        let gap = 3 / (32 * Double.pi)
        for diameter in sizes {
            let g = DayRingGeometry(diameter: diameter)
            for target in 1...12 {
                let span = 1.0 / Double(target) - gap
                guard span > 0 else { continue }
                #expect(
                    isNear(g.cornerRadius(span: span), g.band * DayRingGeometry.cornerRatio),
                    "the clamp binds at \(target) on \(diameter)pt"
                )
            }
        }
    }

    @Test("A span too small for its corners clamps rather than self-intersecting")
    func cornerClampGuards() {
        // Not reachable from the app — this is the guard doing its job on an
        // input the picker cannot produce.
        let g = DayRingGeometry(diameter: 92)
        let hairSpan = 0.0005
        let arcLength = g.innerRadius * CGFloat(hairSpan * 2 * .pi)
        #expect(g.cornerRadius(span: hairSpan) <= arcLength / 2 + 0.0001)
        #expect(g.cornerRadius(span: hairSpan) < g.band * DayRingGeometry.cornerRatio)
    }

    @Test("Degenerate sizes stay in range rather than going negative")
    func degenerateSizes() {
        #expect(DayRingGeometry(diameter: -10).diameter == 0)
        #expect(DayRingGeometry(diameter: 0).innerRadius == 0)
        #expect(DayRingGeometry(diameter: 0).cornerRadius(span: 0.5) == 0)
        #expect(DayRingGeometry(diameter: 92).cornerRadius(span: 0) == 0)
        #expect(DayRingGeometry(diameter: 92).cornerRadius(span: -1) == 0)
    }
}
