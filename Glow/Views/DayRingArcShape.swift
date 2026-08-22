import SwiftUI

/// One repetition's pill: the region between the ring's two radii, bounded by
/// two angles, with all four corners rounded.
///
/// Returns the *outline's* path — the boundary of that region — so stroking it
/// at the hairline gives a closed silhouette whose interior is left clear.
/// Clear rather than filled black is deliberate and load-bearing; see
/// `DayRingView`.
///
/// Path construction only. Every number comes from the geometry.
struct DayRingArcShape: Shape {
    /// Trim fractions of the full circle: 0 at twelve o'clock, clockwise.
    let start: Double
    let end: Double
    let geometry: DayRingGeometry

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // The outline is stroked, and a stroke straddles its path. Insetting by
        // half the hairline is what puts the pill's *edges* on the annulus
        // rather than half a hairline outside it, so the ring's outer diameter
        // does not move.
        let inset = geometry.hairline / 2
        let outer = geometry.outerRadius - inset
        let inner = geometry.innerRadius + inset
        let span = min(max(end - start, 0), 1)
        guard outer > inner, span > 0 else { return path }

        // A full turn has no radial ends: two concentric circles, which is what
        // a target of 1 draws and what a finished ring closes into.
        guard span < 1 else {
            path.addEllipse(in: square(centre, outer))
            path.addEllipse(in: square(centre, inner))
            return path
        }

        let corner = min(geometry.cornerRadius(span: span), (outer - inner) / 2)
        let a0 = angle(start)
        let a1 = angle(end)
        // How much of each arc a corner eats.
        let dOuter = Double(corner / outer)
        let dInner = Double(corner / inner)

        // `addLine`, never `addLines`: the latter starts a *new* subpath, which
        // detaches the inner arc from the outer one and strokes the pill as two
        // open curves — a lens rather than a band. Measured on screen.
        let outerArc = arcPoints(centre, outer, from: a0 + dOuter, to: a1 - dOuter)
        path.move(to: outerArc[0])
        for step in outerArc.dropFirst() { path.addLine(to: step) }
        path.addQuadCurve(to: point(centre, outer - corner, a1), control: point(centre, outer, a1))
        path.addLine(to: point(centre, inner + corner, a1))
        path.addQuadCurve(to: point(centre, inner, a1 - dInner), control: point(centre, inner, a1))
        for step in arcPoints(centre, inner, from: a1 - dInner, to: a0 + dInner) {
            path.addLine(to: step)
        }
        path.addQuadCurve(to: point(centre, inner + corner, a0), control: point(centre, inner, a0))
        path.addLine(to: point(centre, outer - corner, a0))
        path.addQuadCurve(to: point(centre, outer, a0 + dOuter), control: point(centre, outer, a0))
        path.closeSubpath()
        return path
    }

    private func square(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }

    private func angle(_ fraction: Double) -> Double {
        // Zero at twelve o'clock, clockwise, in a y-down space.
        fraction * 2 * .pi - .pi / 2
    }

    private func point(_ centre: CGPoint, _ radius: CGFloat, _ radians: Double) -> CGPoint {
        CGPoint(
            x: centre.x + radius * CGFloat(cos(radians)),
            y: centre.y + radius * CGFloat(sin(radians))
        )
    }

    /// An arc as a run of short lines rather than `addArc`.
    ///
    /// Sampled on purpose: the deviation from a true circle at one degree a
    /// step is under two thousandths of a point on a 92pt ring, and it removes
    /// every chance of getting `addArc`'s `clockwise` flag wrong in a y-down
    /// space — a sign error that draws the complement of the arc asked for.
    private func arcPoints(
        _ centre: CGPoint, _ radius: CGFloat, from: Double, to: Double
    ) -> [CGPoint] {
        let sweep = to - from
        let steps = max(2, Int((abs(sweep) / (.pi / 180)).rounded(.up)))
        return (0...steps).map { step in
            point(centre, radius, from + sweep * Double(step) / Double(steps))
        }
    }
}

/// The run of logged repetitions: one line on the band's centreline.
///
/// Consecutive logged repetitions merge into one unbroken run — the line
/// crosses the gaps between them, and the divisions only survive between
/// repetitions still open. That is the week grid's rule at a different shape: a
/// run of days there is one bar, not a row of dots.
struct DayRingRunShape: Shape {
    let start: Double
    let end: Double
    let geometry: DayRingGeometry

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = geometry.centreRadius
        let span = min(max(end - start, 0), 1)
        guard radius > 0, span > 0 else { return path }

        // At the goal it closes: one continuous circle, with no break at twelve
        // o'clock where the first gap was. When nothing is left there is
        // nothing to divide.
        guard span < 1 else {
            path.addEllipse(in: CGRect(
                x: centre.x - radius, y: centre.y - radius,
                width: radius * 2, height: radius * 2
            ))
            return path
        }

        let a0 = start * 2 * .pi - .pi / 2
        let a1 = end * 2 * .pi - .pi / 2
        let steps = max(2, Int(((a1 - a0) / (.pi / 180)).rounded(.up)))
        path.addLines((0...steps).map { step in
            let radians = a0 + (a1 - a0) * Double(step) / Double(steps)
            return CGPoint(
                x: centre.x + radius * CGFloat(cos(radians)),
                y: centre.y + radius * CGFloat(sin(radians))
            )
        })
        return path
    }
}
