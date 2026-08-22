import CoreGraphics

/// Every size the Today ring draws, derived from one diameter.
///
/// Here rather than in the view because it is arithmetic and the app and the
/// two widgets have to agree about it: the 92pt app ring, the 96pt small widget
/// ring and the 76pt medium one are one drawing at three sizes, and nothing in
/// this type is a point value anybody typed.
///
/// Pure, per the `WeekGrid` / `SlotLayout` pattern — no views, no `Date()`.
struct DayRingGeometry: Equatable, Sendable {
    /// The ring's outer diameter. Everything below is a fraction of it.
    let diameter: CGFloat

    init(diameter: CGFloat) {
        self.diameter = max(0, diameter)
    }

    /// The annulus a repetition occupies: the same stroke-to-size ratio the
    /// week grid's open ring uses, so the two rings stay one drawing.
    var band: CGFloat { diameter * GlowShape.ringWeight }

    /// The weight of every line the ring draws — the pill's outline and the
    /// logged run alike.
    ///
    /// One constant for both is what makes the ring read as one drawing rather
    /// than as two things sharing a circle. A fifth of the band; at 92pt that
    /// lands on 1.58, within a rounding error of the 1.5pt hairline the week
    /// grid already uses. The fraction is the source, not the point value.
    var hairline: CGFloat { diameter * GlowShape.ringHairlineWeight }

    var outerRadius: CGFloat { diameter / 2 }
    var innerRadius: CGFloat { max(0, outerRadius - band) }
    /// Where a logged repetition's line sits, so the ring's silhouette reads at
    /// the same diameter whether a repetition is open or done.
    var centreRadius: CGFloat { outerRadius - band / 2 }

    /// The corner radius of a pill covering `span` of the circle.
    ///
    /// A quarter of the band at all four corners — both radial ends, inner edge
    /// and outer. This replaces a round line cap, which is a corner radius of
    /// *half* the band and is why the ring used to read as a row of lozenges.
    ///
    /// The clamp is a guard rather than a working limit. The tightest supported
    /// case is twelve repetitions on the 76pt widget ring, where the pill is
    /// 11.7 x 6.5pt against a 1.63pt radius — nowhere near binding. A shape
    /// that can self-intersect on an unsupported input still should not.
    func cornerRadius(span: Double) -> CGFloat {
        guard span > 0, innerRadius > 0 else { return 0 }
        let arcLength = innerRadius * CGFloat(min(span, 1) * 2 * .pi)
        let shortestSide = min(band, arcLength)
        return max(0, min(band * Self.cornerRatio, shortestSide / 2))
    }

    /// A quarter of the band.
    static let cornerRatio: CGFloat = 0.25
}
