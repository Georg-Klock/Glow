import Foundation

/// The Today ring: one arc per repetition, closing as the day is logged.
///
/// The ring is the inverse of the fitness rings it resembles. It starts as
/// twelve o'clock's worth of outlined pills — the whole day still open — and
/// each completion turns one into a line, so the ring's *shape* says what is
/// left and its light says the habit was touched at all.
///
/// **Both states glow** (#75). Open is a band, done is a line, and both are
/// lit — which is what the rest of the app has always done and what SPEC §1
/// says in as many words. This ring was the last surface painting a completion
/// grey, on a reading of the rule that made light a reward for being unfinished
/// rather than a mark on the habit.
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
    /// stay twelve visible arcs rather than a ring of holes. **The clamp is
    /// dormant** since #75 halved the gap: the worst supported case is twelve
    /// repetitions, 15° of slice against a 10.74° gap. It stays as a guard.
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

    /// What a tap leaves the day's count at: one more, or zero from a full ring.
    ///
    /// The reset is the whole undo. It is cheap at a target of 3 and costs
    /// eleven taps at 12, which is the accepted trade: the arcs make a mis-tap
    /// visible at a glance, and a separate undo affordance would be a second
    /// control on a surface whose argument is that it has one.
    ///
    /// A count past the target — reachable by editing a habit from 8x down to
    /// 3x — resets the same way a full ring does: the ring was quiet, so the
    /// tap asked for a fresh start, not a ninth repetition.
    static func countAfterTap(count: Int, target: Int) -> Int {
        let goal = max(1, min(target, Frequency.selectableDailyCounts.upperBound))
        let current = max(0, count)
        return current >= goal ? 0 : current + 1
    }

    /// The clear space between two neighbouring repetitions: one band width of
    /// it, measured along the band's centreline.
    ///
    /// **Literal clear space, and that is the change** (#75). This used to be
    /// *two* band widths, and the doubling was not spacing — it was one width
    /// for the round caps plus one of air, because a round cap extends a stroke
    /// half its width past each trim endpoint and two arcs a bare width apart
    /// were visually touching. A pill is bounded exactly by its own start and
    /// end angles and rounds its corners *inside* that span, so nothing extends
    /// past the trim any more and the cap allowance has nothing to pay for.
    ///
    /// One band width, because the ring's only spacing unit is its own
    /// thickness. Both scale with the diameter, so this is a constant angle at
    /// every size: `3 / (32π)` of the circle, **10.74°**, down from 21.49°.
    ///
    /// Segment spans, for the record: 169.26° at a target of 2, 109.26° at 3,
    /// 49.26° at 6, 19.26° at 12.
    static func gapFraction(strokeWidth: Double, diameter: Double) -> Double {
        let centreline = Double.pi * (diameter - strokeWidth)
        guard centreline > 0 else { return 0 }
        return strokeWidth / centreline
    }
}
