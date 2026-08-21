import Foundation

/// The Today ring: one arc per repetition, closing as the day is logged.
///
/// The ring is the inverse of the fitness rings it resembles. It starts full
/// and glowing — the whole day still open — and each completion quiets one arc,
/// so what glows is always what is left to do. At the goal the ring is quiet.
/// That is the same rule as every other mark in the app: the glow means still
/// open, never a reward for finishing.
///
/// Pure geometry over fractions of a circle, so it is testable without a
/// renderer and the app and the widget cannot disagree about where an arc
/// falls. Zero is twelve o'clock and fractions run clockwise, which is also
/// the direction completions consume the ring: the quiet share grows from the
/// top the way a fitness ring fills, and the glow recedes ahead of it.
enum DayRing {
    /// One repetition's share of the ring.
    struct Arc: Identifiable, Equatable, Sendable {
        let index: Int
        /// Trim fractions of the full circle: 0 at twelve o'clock, running
        /// clockwise. Half the gap sits on each side of the slice, so arcs
        /// are centred in their shares and the gaps are uniform.
        let start: Double
        let end: Double
        /// Still to do today — the glowing share. False once its repetition
        /// is logged.
        let isOpen: Bool

        var id: Int { index }
    }

    /// The row of arcs for a day: `target` of them, the first `done` quiet.
    ///
    /// At a target of 1 the ring is a single unbroken circle whatever the gap,
    /// because a gap would imply a division that is not there.
    ///
    /// `gap` is the space between neighbouring arcs as a fraction of the whole
    /// circle. It is clamped to half a slice, so no gap can grow until the
    /// arcs it separates are smaller than it — twelve arcs on a small ring
    /// stay twelve visible arcs rather than a ring of holes.
    static func arcs(target: Int, done: Int, gap: Double = 0) -> [Arc] {
        let count = max(1, min(target, Frequency.selectableDailyCounts.upperBound))
        let quiet = max(0, min(done, count))

        guard count > 1 else {
            return [Arc(index: 0, start: 0, end: 1, isOpen: quiet == 0)]
        }

        let slice = 1.0 / Double(count)
        let clearance = min(max(gap, 0), slice / 2)

        return (0..<count).map { index in
            Arc(
                index: index,
                start: Double(index) * slice + clearance / 2,
                end: Double(index + 1) * slice - clearance / 2,
                isOpen: index >= quiet
            )
        }
    }

    /// The gap that keeps two round-capped arcs reading as separate.
    ///
    /// A round cap extends the stroke by half its width at each end, so two
    /// arcs whose trims are a bare stroke-width apart are visually touching.
    /// One stroke-width for the caps plus one of clear space, measured along
    /// the stroke's centreline — which for a stroke kept inside `diameter`
    /// is inset by half the stroke from the outer edge.
    static func gapFraction(strokeWidth: Double, diameter: Double) -> Double {
        let centreline = Double.pi * (diameter - strokeWidth)
        guard centreline > 0 else { return 0 }
        return (2 * strokeWidth) / centreline
    }
}
